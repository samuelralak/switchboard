# frozen_string_literal: true

module Catalog
	module ServiceDetail
		# The consumer-facing service detail shown in the right slide-over drawer when a buyer
		# clicks a catalog listing. Mirrors the prototype's viewService (mode, description,
		# provider, price, escrow-every-job, input schema, conformance, and the "Request this
		# service" CTA), rendering from Catalog::Listing and gracefully omitting fields a real
		# kind-30402 event does not carry (schema, capability, mode).
		class ServiceDetailComponent < ApplicationComponent
			attr_reader :listing

			def initialize(listing:)
				@listing = listing
			end

			def automated? = listing.fulfillment == "automated"

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
