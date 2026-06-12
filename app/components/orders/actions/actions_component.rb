# frozen_string_literal: true

module Orders
	module Actions
		# The order's action area, branching by state and the viewer's role: the consumer funds (awaiting)
		# then releases or refunds (funded); the provider verifies then redeems (funded). Each panel wires the
		# browser controller (funding / settlement) that does the Cashu work. render? hides it for everyone else
		# and in terminal states.
		class ActionsComponent < ApplicationComponent
			attr_reader :order, :viewer

			def initialize(order:, viewer:)
				@order = order
				@viewer = viewer
			end

			def render? = fund? || release? || settle? || redeem_after_ruling?

			def fund? = awaiting? && consumer?
			def release? = funded? && consumer?
			# The consumer revealed the preimage AND a delivery is recorded: show the awaiting-redemption state,
			# keep only Refund. Gated on delivery to match the lifecycle (a release reflects after delivery).
			def released? = order.release.present? && order.delivery.present?
			# Provider can deliver the result AND verify/redeem once funded (both live in the settle? branch).
			def settle? = funded? && provider?

			# Either party can escalate a funded tier-2 order to the arbiter, until a dispute already exists or the
			# consumer has authorized a release (a release cannot then be clawed back via a dispute).
			def dispute? = funded? && order.tier2? && party? && order.dispute.blank? && order.release.blank?
			# After the operator rules, the favoured party completes the 2-of-3 spend with the arbiter's sig.
			def redeem_after_ruling? = disputed? && order.tier2? && viewer.pubkey == ruling_winner_pubkey

			def relays_json = NostrClient.configuration.relays.to_json
			# Gift-wraps (the delivered result) use the NIP-17 inbox relay set, matching the consumer result panel.
			def dm_relays_json = NostrClient.configuration.dm_relays.to_json

			# A tier-2 lock must clear the tier-2 minimum locktime lead (so a dispute can resolve before the
			# consumer's unilateral refund opens); the default already exceeds it, but take the max defensively.
			def locktime_seconds
				return Orders::Policy.default_locktime_seconds unless order.tier2?

				[ Orders::Policy.default_locktime_seconds, Orders::Policy.tier2_min_locktime.to_i ].max
			end

			# The platform arbiter the consumer locks the 2-of-3 to (nil for a tier-1 order). Funding VALIDATES
			# this equals the platform key and rejects any other, so the browser must source it from here. The
			# recorded order.lock.arbiter_pubkey is the same value once funded; the live key covers funding too.
			def arbiter_pubkey
				order.lock&.arbiter_pubkey || Escrow::ArbiterSigner.pubkey if order.tier2?
			end

			# Absolute URL of the NIP-98 arbiter-signatures endpoint, pinned to the server's canonical origin so
			# the NIP-98 `u` tag the browser signs matches what the server verifies (a relative path would fail).
			def arbiter_signatures_url
				"#{Rails.application.config.x.canonical_origin}#{helpers.api_order_arbiter_signatures_path(order.id)}"
			end

			private

			def awaiting? = order.current_state == Orders::States::AWAITING_FUNDING
			def funded? = order.current_state == Orders::States::FUNDED
			def disputed? = order.current_state == Orders::States::DISPUTED
			def consumer? = viewer.pubkey == order.consumer_pubkey
			def provider? = viewer.pubkey == order.provider_pubkey
			def party? = consumer? || provider?

			# The pubkey the operator's ruling entitles to redeem with the arbiter (nil until ruled).
			def ruling_winner_pubkey
				return order.provider_pubkey if order.dispute&.ruled_for_provider?

				order.consumer_pubkey if order.dispute&.ruled_for_consumer?
			end
		end
	end
end
