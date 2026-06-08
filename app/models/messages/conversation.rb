# frozen_string_literal: true

module Messages
	# One inbox thread from the provider's perspective: an incoming request a client sent for
	# one of the provider's services. `npub`/`name`/`track`/`peer_pubkey` are the client (npub for
	# display, peer_pubkey the 64-hex trust anchor the browser checks decrypted envelopes against);
	# `description` is the service's committed scope. `inputs` (the filled schema) is server-empty
	# and hydrated client-side from the decrypted order envelope (order_envelope.js); the runtime
	# never sees the request content.
	Conversation = Data.define(
		:id, :service, :cap, :description, :npub, :name, :peer_pubkey, :track, :mode, :sats, :span,
		:state, :created, :deadline, :unread, :note, :inputs, :result
	) do
		def short_npub = npub.length > 16 ? "#{npub[0, 10]}…#{npub[-4..]}" : npub
		def automated? = mode == "automated"
		def unread? = unread
		def terminal? = %i[completed refunded expired].include?(state)

		def section
			return :needs_you if state == :received
			return :done if terminal?

			:in_progress
		end
	end
end
