# frozen_string_literal: true

module Attestation
	# Issues a platform attestation: signs a kind-1985 label, upserts it locally so the catalog reflects the
	# badge at once, and broadcasts it to relays. Idempotent per event id; a no-op when off. The platform signs
	# its OWN label, never the provider's key. Returns the signed label, or nil.
	class Issue < BaseService
		option :event # the listing Event being attested
		option :issuer, default: -> { Issuer.new }
		option :manager, default: -> { NostrClient.manager }

		def call
			return unless Policy.issuing? # feature off, or no signing key
			return unless fee_satisfied?  # the (deferred) paid gate
			return if already_attested?   # one current label per event id

			Events::Upsert.call(event_data: signed) # store locally FIRST: the hosted-catalog badge reads the DB, not relays
			broadcast                               # relay propagation, best-effort (see below)

			signed
		end

		private

		# Relay propagation is best-effort. The local upsert above already drives the catalog badge, so a worker
		# that holds no publish sockets (the single-process web server, where puma's before_worker_boot never
		# runs) logs and moves on rather than failing the attestation or 500ing the report. A publishing-enabled
		# process (the backfill task, or a clustered web worker) still broadcasts in full.
		def broadcast
			manager.publish(signed)
		rescue StandardError => e
			Rails.logger.warn("[attestation] label stored locally but not broadcast: #{e.class}: #{e.message}")
		end

		def signed
			@signed ||= issuer.sign(kind: Events::Kinds::LABEL, tags: label_tags)
		end

		def label_tags
			Label.call(coordinate: event.coordinate, event_id: event.event_id)
		end

		def already_attested?
			Event.of_kind(Events::Kinds::LABEL).by_author(issuer.pubkey).with_tag("e", event.event_id).exists?
		end

		# The paid-listing gate, a pass-through for now so attestation is never blocked on a fee. The real check
		# lands with the payments epic. TODO(payments): when ATTESTATION_REQUIRE_FEE is on, verify a posting fee
		# was paid to the platform for event.coordinate before attesting.
		def fee_satisfied?
			true
		end
	end
end
