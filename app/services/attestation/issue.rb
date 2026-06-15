# frozen_string_literal: true

module Attestation
	# Issues a platform attestation: signs a kind-1985 label, broadcasts it, and upserts it locally so the
	# catalog reflects the badge at once. Idempotent per event id; a no-op when off. The platform signs its OWN
	# label, never the provider's key. Returns the signed label, or nil.
	class Issue < BaseService
		option :event # the listing Event being attested
		option :issuer, default: -> { Issuer.new }
		option :manager, default: -> { NostrClient.manager }

		def call
			return unless Policy.issuing? # feature off, or no signing key
			return unless fee_satisfied?  # the (deferred) paid gate
			return if already_attested?   # one current label per event id

			manager.publish(signed)                 # broadcast to relays
			Events::Upsert.call(event_data: signed) # store locally for an immediate catalog read

			signed
		end

		private

		def signed
			@signed ||= issuer.sign(kind: Events::Kinds::LABEL, tags: label_tags)
		end

		def label_tags
			Label.call(coordinate: event.coordinate, event_id: event.event_id)
		end

		def already_attested?
			Event.of_kind(Events::Kinds::LABEL).by_author(issuer.pubkey).with_tag("e", event.event_id).exists?
		end

		# The paid-listing gate. Free to attest unless ATTESTATION_REQUIRE_FEE is on; the actual payment check
		# (a fee paid outright to the platform npub) lands with the payments epic. Until then, requiring a fee
		# means nothing is attested, which is the honest behavior: the gate exists, just not yet passable.
		def fee_satisfied?
			return true unless Policy.require_fee?

			false # TODO(payments): verify a posting fee was paid for event.coordinate before attesting
		end
	end
end
