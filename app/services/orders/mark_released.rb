# frozen_string_literal: true

module Orders
	# Record the consumer's observable assertion that they released the escrow: the preimage-reveal gift-wrap
	# event id and its timestamp. Stores ONLY observable data (brief 6.3); the preimage itself travels
	# end-to-end over NIP-17 and is never seen by the runtime. Consumer-only; the order must be funded.
	# current_state STAYS funded -- this deliberately does NOT touch the state machine. The mint stays the
	# sole authority for the settled "released" state (reached when the provider redeems and Reconcile sees
	# the spend); this assertion only reflects "the consumer approved, awaiting redemption" in the UI. A
	# re-reveal supersedes the prior assertion (UNIQUE(order_id)).
	class MarkReleased < BaseService
		option :order
		option :reveal_event_id, type: Types::Strict::String
		option :released_at

		def call
			ensure_funded!
			Order.transaction do |txn|
				record!
				# Flip the live lifecycle to "Released, awaiting redemption" on both parties' open pages, after
				# commit, mirroring Orders::Transition and Orders::MarkDelivered.
				txn.after_commit { Orders::Ui::Update.call(order:) }
			end
			order.release
		end

		private

		def ensure_funded!
			return if order.current_state == Orders::States::FUNDED

			raise IllegalTransitionError, "cannot release a #{order.current_state} order"
		end

		# Upsert the single release row; a re-reveal overwrites it with the newer wrap (supersede).
		def record!
			release = order.release || order.build_release
			release.update!(reveal_event_id:, released_at: released_at_time)
		end

		# released_at arrives as a Time (Ruby callers) or unix-seconds (the browser sends the rumor created_at).
		def released_at_time
			@released_at_time ||= unix_time? ? Time.at(released_at.to_i).utc : released_at
		end

		def unix_time? = released_at.is_a?(Numeric) || released_at.to_s.match?(/\A\d+\z/)
	end
end
