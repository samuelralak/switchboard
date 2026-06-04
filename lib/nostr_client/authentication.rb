# frozen_string_literal: true

module NostrClient
	# NIP-42 AUTH responder mixed into Connection. LAZY by design: an unsolicited ["AUTH", challenge]
	# frame only STORES the challenge; we sign the kind-22242 credential and send it ONLY when a gated
	# operation actually needs it (an "auth-required:" OK on a publish, or CLOSED on a subscription),
	# so R_op never reveals its pubkey to a relay that does not gate our requests. On the relay's AUTH
	# OK we reset the attempt counter and re-apply subscriptions; "restricted:" is terminal. The
	# challenge and counters are per-connection and reset on disconnect; an attempt cap stops loops.
	module Authentication
		AUTH_KIND = 22_242
		MAX_AUTH_ATTEMPTS = 3
		MAX_CHALLENGE_BYTES = 1024

		# Remember the relay's challenge without signing anything yet (lazy AUTH).
		def store_challenge(value) = @challenge = value

		# Sign + send the NIP-42 AUTH for the stored challenge. Returns the sent AUTH event, or nil if
		# we cannot authenticate (no signer, no usable challenge, or the attempt cap is reached).
		def authenticate
			return unless can_authenticate?

			@auth_attempts = auth_attempts + 1
			event = auth_event
			@auth_event_id = event["id"]
			send_frame(Messages::Outbound::AUTH, event)
			event
		end

		def challenge = @challenge

		# True when the relay told us to authenticate (vs "restricted:" which is terminal).
		def auth_required?(text) = text.to_s.start_with?("auth-required:")

		# True when +event_id+ is the OK for the AUTH credential we sent (not a normal publish).
		def awaiting_auth_ok?(event_id) = !@auth_event_id.nil? && event_id == @auth_event_id

		# The relay accepted our AUTH: clear the in-flight id, reset the cap, re-apply subscriptions.
		def on_authenticated
			@auth_event_id = nil
			@auth_attempts = 0
			resubscribe
		end

		# The relay rejected our AUTH: clear the in-flight id so a later gated op can retry (capped).
		def on_auth_failed = @auth_event_id = nil

		private

		# Preconditions for sending AUTH: a configured signer, a usable stored challenge, an open
		# socket, and attempts left (the cap stops auth loops).
		def can_authenticate?
			return false unless NostrClient.configuration.auth_signer && valid_challenge? && connected?

			auth_attempts_remaining?
		end

		# A challenge we will actually sign: a non-empty, valid-encoding, bounded string. A relay
		# sending an empty or junk challenge must not make us sign a spec-invalid credential.
		def valid_challenge?
			return false unless @challenge.is_a?(String) && !@challenge.empty?

			@challenge.valid_encoding? && @challenge.bytesize <= MAX_CHALLENGE_BYTES
		end

		# The signed kind-22242 AUTH event; a bearer credential, so it is never logged.
		def auth_event
			tags = [ [ "relay", url ], [ "challenge", @challenge ] ]
			NostrClient.configuration.auth_signer.sign(kind: AUTH_KIND, tags:, content: "")
		end

		def auth_attempts = @auth_attempts ||= 0
		def auth_attempts_remaining? = auth_attempts < MAX_AUTH_ATTEMPTS

		def reset_auth
			@challenge = nil
			@auth_attempts = 0
			@auth_event_id = nil
		end
	end
end
