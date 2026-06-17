# frozen_string_literal: true

module Operational
	# Signs an event with the R_op key and publishes it to every connected relay, returning a
	# NostrClient::PublishResult per relay. R_op's only outbound speech: its own kind-10050 / NIP-89
	# and the opaque escrow-coordination wraps (never a user's message, per the minimize/e2e model).
	class Publish < BaseService
		option :kind, type: Types::Strict::Integer
		option :content, type: Types::Strict::String, default: -> { "" }
		option :tags, default: -> { [] }
		option :signer, default: -> { Signer.new }
		option :manager, default: -> { NostrClient.manager }

		def call
			# R_op's outbound is the NIP-17/59 inbox channel, so it targets ONLY the DM-inbox relays. The web
			# process also holds public catalog connections (for attestation labels); never blanket-publish a
			# wrap to all of them, or it would leak onto public relays.
			manager.publish(signer.sign(kind:, content:, tags:), urls: NostrClient.configuration.dm_relays)
		end
	end
end
