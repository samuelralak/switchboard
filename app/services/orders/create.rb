# frozen_string_literal: true

module Orders
	# Open a new escrow order in awaiting_funding. Validates parties, the mint allowlist, and the per-order cap
	# (CreateContract, also backed by Order model validations); the DB enforces dedupe_key uniqueness, one
	# active order per (consumer, listing) / claim per request, and amount > 0. Idempotent on a repeat order:
	# a dedupe_key re-submit or a second order against an order the actor already has open returns that order.
	class Create < BaseService
		# Caller-provided attributes that identify a logical order, compared on an idempotent re-create.
		IDENTITY = %i[entry_point listing_coordinate consumer_pubkey provider_pubkey amount_sats mint_url tier].freeze

		option :entry_point, type: Types::Coercible::String
		option :consumer_pubkey, type: Types::Strict::String
		option :provider_pubkey, type: Types::Strict::String
		option :listing_coordinate, type: Types::Strict::String
		option :amount_sats, type: Types::Coercible::Integer
		option :mint_url, type: Types::Strict::String
		option :dedupe_key, type: Types::Strict::String
		option :funding_deadline_at
		option :tier, type: Types::Coercible::String, default: -> { Orders::Tiers::TIER1_HTLC }

		def call
			validate!
			order = nil
			Order.transaction do |txn|
				order = Order.create!(attributes)
				# Notify the affected party after commit (a request claim alerts the requester); only a genuinely
				# new order fires this -- an idempotent re-create raises below and never reaches here.
				txn.after_commit { Notifications::ForOrder.call(order:, event: :placed) }
			end
			order
		rescue ActiveRecord::RecordNotUnique
			# A repeat order returns the order it collides with: a dedupe_key re-submit of the same logical order,
			# or the active order the actor already has open for this listing/request. An unrelated collision (a
			# dedupe_key reused for a different request, or another party's claim) has no match and re-raises.
			existing = idempotent_match
			raise unless existing

			existing
		end

		private

		def idempotent_match
			by_key = Order.find_by(dedupe_key:)
			return by_key if by_key && same_order?(by_key)

			active_duplicate
		end

		# The actor's own open order this create duplicates: for a catalog order, the consumer's one active
		# order for the listing; for a request claim, an existing claim only when this actor is the claimer (so
		# a second provider claiming an already-claimed request still re-raises).
		def active_duplicate
			party = entry_point == EntryPoints::CATALOG_ORDER ? { consumer_pubkey: } : { provider_pubkey: }
			Order.active.find_by(entry_point:, listing_coordinate:, **party)
		end

		def same_order?(order)
			IDENTITY.all? { |attr| order.public_send(attr) == public_send(attr) }
		end

		def validate!
			result = CreateContract.new.call(
				entry_point:, consumer_pubkey:, provider_pubkey:, listing_coordinate:,
				amount_sats:, mint_url:, dedupe_key:, tier:, funding_deadline_at:
			)
			raise ValidationError, result.errors(full: true).to_h unless result.success?
		end

		def attributes
			{
				entry_point:, consumer_pubkey:, provider_pubkey:, listing_coordinate:,
				amount_sats:, mint_url:, dedupe_key:, tier:, funding_deadline_at:,
				current_state: Orders::States::AWAITING_FUNDING
			}
		end
	end
end
