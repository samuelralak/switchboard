# frozen_string_literal: true

module Orders
	# Open an escrow order from a kind-30402 coordinate, placed by the signed-in actor. The amount, the
	# counterparty, AND the escrow tier are read from the listing/request EVENT, never trusted from the
	# client: ordering a listing makes the actor the consumer and honours the buyer's chosen tier; claiming
	# a request makes the actor the provider and inherits the tier the poster funded for (the claimer cannot
	# change it). Escrow locks whole sats.
	class Place < BaseService
		option :coordinate, type: Types::Strict::String
		option :mint_url, type: Types::Strict::String
		option :dedupe_key, type: Types::Strict::String
		option :tier, type: Types::Coercible::String, default: -> { Orders::Tiers::TIER1_HTLC }
		option :actor # the signed-in User

		def call
			deadline = Orders::Policy.funding_window.from_now

			Orders::Create.call(**order_attributes(locate!), mint_url:, dedupe_key:, funding_deadline_at: deadline)
		end

		private

		def locate!
			kind = coordinate.split(":", 2).first.to_i
			raise NotFoundError, "not a kind-30402 coordinate" unless kind == Events::Kinds::CLASSIFIED

			event = Event.by_coordinate(coordinate)
			raise NotFoundError, "listing or request not found" unless event
			raise NotFoundError, "listing or request has expired" if event.expires_at&.past?

			event
		end

		def order_attributes(event)
			request = Requests::OpenRequest.new(event).conforms?
			listing = Catalog::Listing.new(event).conforms?
			raise NotFoundError, "ambiguous listing/request marker" if request && listing

			request ? claim_attributes(event) : listing_order_attributes(event)
		end

		# Claiming an open request: the actor becomes the provider; the request author funds. The tier comes
		# from the request event (the poster opted in when authoring), so the claiming provider's POSTed tier
		# is ignored -- only the funder's choice can move money into arbiter mediation.
		def claim_attributes(event)
			request = Requests::OpenRequest.new(event)
			raise NotFoundError, "request is not open" unless request.open?

			{
				entry_point: EntryPoints::REQUEST_CLAIM, consumer_pubkey: event.pubkey, provider_pubkey: actor.pubkey,
				listing_coordinate: coordinate, amount_sats: whole_sats!(request.budget_amount, request.whole_sat_budget?),
				tier: request.escrow_tier
			}
		end

		# Ordering a catalog listing: the actor becomes the consumer; the listing author is the provider. The
		# consumer is the funder here, so the buyer's chosen tier (gated by ServiceDetail#tier2_offered?) stands.
		def listing_order_attributes(event)
			listing = Catalog::Listing.new(event)
			raise NotFoundError, "not an active service listing" unless listing.conforms? && listing.active?
			raise NotFoundError, "automated fulfillment is not yet available" if listing.automated?

			{
				entry_point: EntryPoints::CATALOG_ORDER, consumer_pubkey: actor.pubkey, provider_pubkey: event.pubkey,
				listing_coordinate: coordinate, amount_sats: whole_sats!(listing.price_amount, listing.whole_sat_price?),
				tier: tier
			}
		end

		# The presenter (whole_sat_price?/whole_sat_budget?) is the single source of the rule; this raises a
		# clear error when it fails, so the UI gate and the server enforcement can never drift.
		def whole_sats!(amount, valid)
			raise ValidationError, { amount_sats: [ "must be a whole-sat amount" ] } unless valid

			amount
		end
	end
end
