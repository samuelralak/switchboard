# frozen_string_literal: true

module Attestation
	# Single source of truth for the attestation feature: the catalog policy, the env-scoped label namespace,
	# the (public) issuer pubkey to verify labels against, and the read helpers the catalog uses to ask "is this
	# listing attested?". A config reader (mirrors Orders::Policy), not a DB role. The issuer pubkey is resolved
	# from an explicit ATTESTATION_PUBKEY or by deriving it from the issuing key, so the read path never needs
	# the private key.
	module Policy
		module_function

		def config
			Rails.application.config.x.attestation
		end

		# off | badge | exclude. An unset/unknown value falls back to the default.
		def policy
			raw = config.policy.to_s
			POLICIES.include?(raw) ? raw : DEFAULT_POLICY
		end

		def off?
			policy == "off"
		end

		def badge?
			policy == "badge"
		end

		def exclude?
			policy == "exclude"
		end

		# Env-scoped label namespace (prod bare, other envs suffixed), so non-prod labels never validate in prod.
		def namespace
			Rails.env.production? ? NAMESPACE_BASE : "#{NAMESPACE_BASE}-#{Rails.env}"
		end

		def require_fee?
			config.require_fee == true
		end

		# The public key whose kind-1985 labels we trust: explicit (a reader verifying another issuer) or derived
		# from our own issuing key. nil when neither is available, which disables the feature.
		def issuer_pubkey
			return @issuer_pubkey if defined?(@issuer_pubkey)

			@issuer_pubkey = config.explicit_pubkey.presence || derived_issuer_pubkey
		end

		def derived_issuer_pubkey
			return nil unless Issuer.configured?

			Issuer.new.pubkey
		end

		# Can we READ/surface attestations (badge or exclude)? Needs a policy and a known issuer.
		def enabled?
			!off? && issuer_pubkey.present?
		end

		# Can we ISSUE attestations? Needs a policy and a signing key.
		def issuing?
			!off? && Issuer.configured?
		end

		# Should a listing be surfaced in the catalog given the policy? Always under off/badge; only when
		# attested under exclude. Keeps the policy decision here rather than in the broadcast service.
		def surfaceable?(listing)
			return true unless enabled? && exclude?

			listing.attested?
		end

		# Does the listing event carry a current, issuer-signed attestation? Strict on the event id (the e-tag),
		# so editing a listing (a new event at the same coordinate) drops the badge until it is re-attested,
		# closing the silent-swap hole.
		def attested?(event)
			return false unless enabled?

			labels_by_issuer.with_tag("e", event.event_id).exists?
		end

		# Bulk-load attestation status onto a collection of presenters (service listings or open requests) in
		# one query, so each card's badge needs no extra round-trip. Returns the same collection.
		def mark(presentables)
			return presentables unless enabled?

			attested = attested_ids(presentables.map { |item| item.event.event_id })
			presentables.each { |item| item.attested = attested.include?(item.event.event_id) }
		end

		# Batch form: the subset of `event_ids` that carry a current attestation, in one query (avoids an N+1
		# over the cards).
		def attested_ids(event_ids)
			ids = Array(event_ids).uniq
			return Set.new unless enabled? && ids.any?

			attested_among(ids) & ids.to_set
		end

		def attested_among(ids)
			conditions = Array.new(ids.size, "tags @> ?").join(" OR ")
			bindings = ids.map { |id| [ [ "e", id ] ].to_json }
			labels_by_issuer.where(conditions, *bindings).pluck(:tags).flat_map { |tags| e_tag_values(tags) }.to_set
		end

		# Issuer-signed "listed" labels in THIS env's namespace. Pinning the full ["l", LABEL_VALUE, namespace]
		# tag (not just the issuer) makes the env-scoped namespace actually enforce on read, so a non-prod label
		# never validates in prod even if an issuer key were shared, and a future issuer label of another kind is
		# not mistaken for an attestation.
		def labels_by_issuer
			listed = [ [ "l", LABEL_VALUE, namespace ] ].to_json
			Event.of_kind(Events::Kinds::LABEL).by_author(issuer_pubkey).where("tags @> ?", listed)
		end

		def e_tag_values(tags)
			tags.select { |tag| tag.is_a?(Array) && tag[0] == "e" }.pluck(1)
		end
	end
end
