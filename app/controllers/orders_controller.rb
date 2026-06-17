# frozen_string_literal: true

# Session-authed escrow order lifecycle for the signed-in browser: place an order from a listing/request
# coordinate, report the HTLC funding lock, and track its state. The browser does the Cashu locking/keys;
# Rails records only observable lock data (non-custodial).
class OrdersController < ApplicationController
	include RedirectsOnError

	before_action :require_login
	# Limit only the mutating/money actions; the hub + order pages are GETs browsed freely (tab switches and
	# order selections are page loads, so limiting them 429s normal browsing).
	rate_limit to: 20, within: 1.minute, by: -> { current_user&.pubkey },
		only: %i[create fund deliver release settle dispute]

	# The order activity hub: a tabbed ledger of everything the signed-in user is BUYING (orders they placed +
	# requests they posted) and SELLING (orders they provide on). Replaces the separate My-requests + Messages
	# index pages; rows open the order's drawer / its thread. Reuses the existing ledger + provider-inbox queries.
	def index
		@hub = Orders::Ui::State.hub(pubkey: current_user.pubkey, tab: params[:tab], order_id: params[:order_id])
	end

	def show
		@order = Order.involving(current_user.pubkey).find(params.expect(:id))
		# Reflect funding-window expiry the moment the order is viewed, rather than waiting on the background
		# sweep: a thin, idempotent transition through the sole state writer (no-op unless past the deadline).
		Orders::ExpireIfDue.call(order: @order)
	end

	def create
		order = Orders::Place.call(actor: current_user, **place_params)

		redirect_to order_path(order), notice: placed_notice(order)
	end

	def fund
		order = Order.as_consumer(current_user.pubkey).find(params.expect(:id)) # only the consumer funds
		Orders::Funding.call(order:, **funding_params)

		redirect_to order_path(order), notice: "Escrow funded."
	end

	# The provider records the observable delivery assertion after sealing the result E2E (order_result
	# controller). Off the money path; the result content itself never reaches the server.
	def deliver
		order = Order.as_provider(current_user.pubkey).find(params.expect(:id)) # only the provider delivers
		Orders::MarkDelivered.call(order:, **delivery_params)

		head :created
	end

	# The consumer records the observable release assertion after revealing the preimage to the provider over
	# NIP-17 (settlement controller). Off the money path; the preimage never reaches the server, and
	# current_state stays funded until the mint confirms the provider's redemption.
	def release
		order = Order.as_consumer(current_user.pubkey).find(params.expect(:id)) # only the consumer releases
		Orders::MarkReleased.call(order:, **release_params)

		head :created
	end

	# Either party asks Rails to re-derive the order's state from the mint right after a spend (the provider
	# redeemed, or the consumer refunded), so settlement registers immediately instead of waiting for the
	# sweep. The mint is the sole authority; Reconcile is idempotent and a no-op until the proofs move.
	def settle
		order = Order.involving(current_user.pubkey).find(params.expect(:id))
		Orders::Reconcile.call(order:)

		head :ok
	rescue Cashu::MintError
		head :accepted # the mint is unreachable right now; the reconcile sweep will retry
	end

	# Either party escalates a funded Tier-2 order to the platform arbiter. Moves it to `disputed`; the consumer
	# keeps the post-locktime refund backstop throughout. OpenDispute rejects tier-1, non-parties, non-funded.
	def dispute
		order = Order.involving(current_user.pubkey).find(params.expect(:id))
		Orders::OpenDispute.call(order:, opened_by_pubkey: current_user.pubkey, reason: dispute_reason)

		redirect_to order_path(order), notice: "Dispute opened. The platform arbiter will review it."
	end

	private

	# A catalog buyer funds immediately, so they are told to fund. A request CLAIMER is the provider and the
	# POSTER funds the budget, so the claimer must never be told to fund the escrow.
	def placed_notice(order)
		# An idempotent re-hit (one active order per consumer/listing) returns the EXISTING order, not a new one.
		# Say so honestly: a buyer who changed the hours must not think they placed a new order at the new total
		# when they actually landed on the prior one at its own amount.
		if !order.previously_new_record? && order.entry_point == Orders::EntryPoints::CATALOG_ORDER
			return "You already have an open order for this service. Fund or cancel it before placing a different one."
		end

		if order.entry_point == Orders::EntryPoints::REQUEST_CLAIM
			"Request claimed. The poster will lock the budget to you, then you can deliver."
		else
			"Order placed. Fund the escrow to begin."
		end
	end

	def place_params
		params.expect(order: %i[coordinate mint_url dedupe_key tier hours]).to_h.symbolize_keys
	end

	def funding_params
		params.expect(order: [ :mint_url, :hashlock, :locktime, :lock_pubkey, :refund_pubkey, :arbiter_pubkey,
			:required_signatures, :required_refund_signatures, { proofs: [ %i[y amount keyset_id] ] } ]).to_h.deep_symbolize_keys
	end

	def delivery_params
		params.expect(delivery: %i[delivery_event_id delivered_at content_hash]).to_h.symbolize_keys
	end

	def release_params
		params.expect(release: %i[reveal_event_id released_at]).to_h.symbolize_keys
	end

	# Reason is optional; a bare dispute (no params) is allowed.
	def dispute_reason
		params.fetch(:dispute, {}).permit(:reason)[:reason]
	end
end
