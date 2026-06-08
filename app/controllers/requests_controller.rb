# frozen_string_literal: true

# Open requests (funded bounties, brief §10.2): the demand-side mirror of the studio. `index` is "My
# requests" — the signed-in consumer's own posted requests (the public browse lives on the catalog's
# Open-requests lens); `new` authors one in a single-column form with a section rail; `preview` renders
# the on-demand drawer from the in-flight form params. Posting is non-custodial (the browser signs +
# broadcasts the kind-30402 request with the consumer's key), so there is no create POST.
class RequestsController < ApplicationController
	include PublishesInBrowser

	before_action :require_login
	before_action :set_compose_context, only: :new

	# Fields the form posts to #preview; shape the draft. The shared CARRY_KEYS come from PublishesInBrowser.
	PREVIEW_KEYS = %i[title description capability budget delivery_value delivery_unit claim_value claim_unit].freeze

	# "My requests" is the consumer's ledger: the orders they placed/claimed (Orders::Ledger) plus the
	# requests they posted that are still awaiting a claim (the board, scoped to them).
	def index
		@orders = Orders::Ledger.call(pubkey: current_user.pubkey)
		@board = Requests::Ui::State.grid(pubkey: current_user.pubkey)
		@open_order = @orders.find { |row| row.id == params[:order_id] } # ?order_id opens that order's drawer
	end

	def new
		@draft = Requests::Draft.open_request({}, pubkey: @pubkey)
	end

	# On-demand preview: builds a draft OpenRequest from the in-flight form and renders the very component
	# the board uses, swapped into the turbo frame inside the preview drawer.
	def preview
		draft = Requests::Draft.open_request(draft_params, pubkey: current_user.pubkey)
		render partial: "requests/preview", locals: { request: draft }
	end

	private

	def draft_params = preview_params(*PREVIEW_KEYS)
end
