# frozen_string_literal: true

# Open requests (funded bounties, brief §10.2): the demand-side mirror of the studio. `index` is "My
# requests" — the signed-in consumer's own posted requests (the public browse lives on the catalog's
# Open-requests lens); `new` authors one in a single-column form with a section rail; `preview` renders
# the on-demand drawer from the in-flight form params. Posting is non-custodial (the browser signs +
# broadcasts the kind-30402 request with the consumer's key), so there is no create POST.
class RequestsController < ApplicationController
	before_action :require_login
	before_action :set_compose_context, only: :new

	# Fields the form posts to #preview. PREVIEW_KEYS shape the draft; CARRY_KEYS carry an existing request
	# through an edit (ignored by the Draft, permitted so the POST logs no unpermitted params).
	PREVIEW_KEYS = %i[title description capability budget delivery_value delivery_unit claim_value claim_unit].freeze
	CARRY_KEYS = %i[d_tag status published_at created_at].freeze

	def index
		@board = Requests::Ui::State.grid(pubkey: current_user.pubkey)
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

	def set_compose_context
		@pubkey = current_user.pubkey
		@publish_relays = NostrClient.configuration.relays # the catalog relays; post there so it is catalogued
		@btc_usd = Pricing::BtcRate.call # nil hides the fiat hint; never blocks the render
	end

	def draft_params
		# Drop the framework CSRF token before permit (still verified by Rails before this action runs);
		# otherwise it logs as an unpermitted parameter on every preview POST.
		params.except(:authenticity_token).permit(*PREVIEW_KEYS, *CARRY_KEYS).to_h
	end
end
