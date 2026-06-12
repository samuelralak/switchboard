# frozen_string_literal: true

module Catalog
	module ServiceDetail
		# The consumer-facing service detail shown in the right slide-over drawer when a buyer
		# clicks a catalog listing. Mirrors the prototype's viewService (mode, description,
		# provider, price, escrow-every-job, input schema, conformance, and the "Request this
		# service" CTA), rendering from Catalog::Listing and gracefully omitting fields a real
		# kind-30402 event does not carry (schema, capability, mode).
		class ServiceDetailComponent < ApplicationComponent
			attr_reader :listing, :show_cta

			# show_cta: false drops the buyer action (the provider reuses this same detail in the messages
			# drawer, where ordering their own service makes no sense).
			def initialize(listing:, show_cta: true)
				@listing = listing
				@show_cta = show_cta
			end

			def automated? = listing.fulfillment == "automated"

			# The addressable coordinate the order is placed against (kind:pubkey:d).
			def order_coordinate = listing.coordinate

			# Escrow locks whole sats, so only a fixed whole-sat listing (with a vetted mint available) is
			# directly orderable; per-hour / non-sat / price-on-request listings keep the inert CTA for now.
			def orderable? = Orders::Policy.default_mint.present? && !listing.per_hour? && listing.whole_sat_price?

			# Offer the Tier-2 (arbiter-mediated) escrow choice only when the platform arbiter is provisioned AND
			# the price sits under the lower Tier-2 cap; otherwise the buyer would place an unfundable order
			# (Orders::Funding#ensure_tier_available! + the per-tier cap reject it). Tier-1 stays the default.
			def tier2_offered?
				Escrow::ArbiterSigner.pubkey.present? && listing.price_amount.to_i <= Orders::Policy.tier2_max_order_sats
			end

			# The pricing-basis caption under the price (the PriceTag carries the amount + currency).
			def price_basis_label = listing.per_hour? ? "per hour" : "per request"

			# A manual service's turnaround, e.g. "delivers in 24h"; nil when none is declared.
			def delivery_label
				listing.delivery_window.presence && "delivers in #{listing.delivery_window}"
			end

			# The escrow-flow note under the CTA. A per-hour total is settled at order time (rate x hours),
			# so it is not stated as a fixed amount.
			def request_note
				if listing.per_hour?
					"Add your inputs, agree the hours, then lock the total in escrow. Escrow releases to the " \
						"provider only when the work arrives."
				elsif listing.price?
					"Add your inputs, lock #{helpers.number_with_delimiter(listing.price_amount)} " \
						"#{listing.price_currency} in escrow, then track delivery. Escrow releases to the " \
						"provider only when the work arrives."
				end
			end

			# Escrow framed as the buyer's guarantee; mode-specific when the listing declares one.
			def escrow_explainer
				case listing.fulfillment
				when "automated"
					"Automated escrow. Funds lock as a Lightning hold invoice, released on a valid response " \
						"and auto-cancelled on timeout. Genuinely trustless for fast work."
				when "manual"
					"Manual escrow. Funds lock as key-locked Cashu (NUT-11 P2PK) with a timelock refund if the " \
						"provider misses the delivery window. Locked to keys, never held by us."
				else
					"Every job is escrowed. Funds lock at request and release only on delivery, with an automatic " \
						"refund if the work never arrives. The platform guarantees it, not the provider."
				end
			end
		end
	end
end
