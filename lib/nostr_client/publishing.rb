# frozen_string_literal: true

module NostrClient
	# Publish + OK-correlation concern mixed into Connection. Send an EVENT and block (off the
	# reactor) until the relay's OK, a timeout, or a disconnect; the pending registry is touched
	# ONLY on the reactor thread and the caller waits on a thread-safe queue. An "auth-required:"
	# rejection (NIP-42) defers the EVENT, authenticates, and re-sends it once the relay accepts
	# the AUTH, so the first write to an AUTH-gated relay is delivered, not silently dropped.
	module Publishing
		# Schedule the EVENT on the reactor and return the queue the caller blocks on; a disconnected
		# relay resolves immediately. Split from #publish so Manager can arm N relays before popping.
		def publish_async(event_hash)
			queue = Thread::Queue.new
			if connected?
				Reactor.instance.schedule { register_and_send(event_hash.fetch("id"), queue, event_hash) }
			else
				queue.push(PublishResult.new(url:, status: :error, message: "not connected"))
			end
			queue
		end

		def publish(event_hash) = publish_async(event_hash).pop

		# Resolves a pending publish from the relay's OK frame (reactor thread, via Manager). An OK for
		# our own AUTH credential drives the auth state machine; an "auth-required:" rejection defers
		# the EVENT for re-send after AUTH; "restricted:" and every other rejection are terminal.
		def settle_ok(event_id, accepted, text)
			return resolve_auth(accepted) if awaiting_auth_ok?(event_id)
			return settle(event_id, status: :ok, message: text) if accepted
			return settle(event_id, status: :rejected, message: text) unless auth_required?(text)

			defer_until_authenticated(event_id, text)
		end

		private

		def pending = @pending ||= {}
		def timers = @timers ||= {}

		# Reactor thread: register the pending publish, arm a timeout, send the EVENT frame. A second
		# publish of the same (deterministic NIP-01) id while the first is in flight fails fast rather
		# than orphaning the first caller's queue and leaking its timer.
		def register_and_send(id, queue, event_hash)
			return reject(queue, "not connected") unless connected?
			return reject(queue, "duplicate in-flight publish") if pending.key?(id)

			pending[id] = { queue:, event: event_hash }
			arm_timeout(id) { settle(id, status: :timeout, message: nil) }
			send_event(id, event_hash)
		end

		def reject(queue, message) = queue.push(PublishResult.new(url:, status: :error, message:))

		# Write the EVENT frame; a raise from the socket settles this caller as :error now rather than making
		# it wait out the full publish timeout (the reactor error_handler keeps the reactor alive regardless).
		def send_event(id, event_hash)
			@socket.send([ Messages::Outbound::EVENT, event_hash ].to_json)
		rescue StandardError => e
			settle(id, status: :error, message: e.message)
		end

		# Reactor thread: deliver the result and clean up (idempotent: whichever of OK / timeout /
		# disconnect fires first wins, the rest no-op via the delete).
		def settle(event_id, status:, message:)
			entry = pending.delete(event_id) or return

			cancel_timeout(event_id)
			entry[:queue].push(PublishResult.new(url:, status:, message:))
		end

		# Arm (replacing any current) / cancel the publish timeout for +id+. A seam over EM so the timeout
		# is re-armed cleanly when a publish is deferred for AUTH and again when it is re-sent.
		def arm_timeout(id, &)
			cancel_timeout(id)
			timeout = NostrClient.configuration.publish_timeout_seconds
			timers[id] = EM.add_timer(timeout, &)
		end

		def cancel_timeout(id)
			timer = timers.delete(id) or return

			EM.cancel_timer(timer)
		end

		# Reactor thread (on_close): fail every in-flight publish (dup so settle can delete).
		def fail_all(reason) = pending.dup.each_key { |id| settle(id, status: :error, message: reason) }

		# An "auth-required:" EVENT rejection: keep the pending entry, mark it for re-send, and
		# authenticate. If we cannot authenticate (no signer/challenge, or the cap is reached), settle
		# it now so the caller is never left blocked.
		def defer_until_authenticated(event_id, text)
			entry = pending[event_id] or return

			entry[:awaiting] = true
			# AUTH may take a moment: replace the original publish timeout with a fresh window so a slow
			# AUTH does not falsely time out the publish, and the caller still unblocks if AUTH stalls.
			arm_timeout(event_id) { settle_auth_wait(event_id) }
			# Initiate AUTH, or -- if one is already in flight -- just wait for it (every deferred event is
			# re-sent when that single AUTH resolves). Settle now only when AUTH is impossible (no signer /
			# cap reached) and there is nothing in flight to wait on, so the caller is never left blocked.
			settle(event_id, status: :auth_required, message: text) unless authenticate || auth_in_flight?
		end

		# The AUTH-wait timer fired: the relay took our credential but never OK'd it. Unblock this caller,
		# and release the in-flight id so the next gated op can re-AUTH within the (monotonic) cap -- unless
		# a sibling still awaits this same AUTH, whose late OK would re-send it. @auth_attempts is NOT reset:
		# the stall still spent one capped attempt, keeping the C8 bound against a black-holing relay.
		def settle_auth_wait(event_id)
			settle(event_id, status: :auth_required, message: "auth timed out")
			on_auth_failed if pending.none? { |_id, entry| entry[:awaiting] }
		end

		# Reactor thread: the OK for our AUTH credential. On success re-send every deferred EVENT (the
		# original per-publish timeout still bounds it); on failure settle them so callers unblock.
		def resolve_auth(accepted)
			if accepted
				resend_deferred
				on_authenticated
			else
				on_auth_failed
				settle_deferred
			end
		end

		# AUTH succeeded: re-send every deferred EVENT, each under a FRESH publish timeout (the original
		# was replaced by the AUTH-wait window in defer_until_authenticated), so a publish that waited on
		# AUTH still gets a full window for its OK instead of inheriting the elapsed one.
		def resend_deferred
			# Iterate a snapshot: send_event may settle (and so delete from pending) on a socket error.
			pending.select { |_id, entry| entry[:awaiting] }.each do |id, entry|
				entry[:awaiting] = false
				arm_timeout(id) { settle(id, status: :timeout, message: nil) }
				send_event(id, entry[:event])
			end
		end

		def settle_deferred
			awaiting = pending.select { |_id, entry| entry[:awaiting] }.keys
			awaiting.each { |id| settle(id, status: :auth_required, message: "auth failed") }
		end
	end
end
