# frozen_string_literal: true

module Messages
	# One inbox thread from the provider's perspective: an incoming request a client sent for
	# one of the provider's services. `npub`/`name`/`track` are the client and their signed
	# history; `description` is the service's committed scope; each `inputs` entry is a filled
	# schema field (`label`/`value`/`type`/`required`). Placeholder today; the gift-wrap
	# decrypt layer will build the same value object from decrypted rumors.
	Conversation = Data.define(
		:id, :service, :cap, :description, :npub, :name, :track, :mode, :sats, :span,
		:state, :created, :deadline, :unread, :note, :inputs, :result
	) do
		def short_npub = npub.length > 16 ? "#{npub[0, 10]}…#{npub[-4..]}" : npub
		def automated? = mode == "automated"
		def unread? = unread
		def terminal? = %i[completed expired failed refunded cancelled].include?(state)

		def section
			return :needs_you if state == :received
			return :done if terminal?

			:in_progress
		end
	end
end
