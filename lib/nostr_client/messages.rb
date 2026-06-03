# frozen_string_literal: true

module NostrClient
	# NIP-01 message types.
	#   Outbound = client -> relay
	#   Inbound  = relay -> client
	module Messages
		module Outbound
			EVENT = "EVENT"
			REQ   = "REQ"
			CLOSE = "CLOSE"
			AUTH  = "AUTH"
		end

		module Inbound
			EVENT  = "EVENT"
			OK     = "OK"
			EOSE   = "EOSE"
			CLOSED = "CLOSED"
			NOTICE = "NOTICE"
			AUTH   = "AUTH"
		end
	end
end
