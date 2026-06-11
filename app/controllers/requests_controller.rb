# frozen_string_literal: true

# Open requests (funded bounties, brief §10.2): the demand-side mirror of the studio. `index` is "My
# requests" — the signed-in consumer's own posted requests (the public browse lives on the catalog's
# Open-requests lens); `new` authors one in a single-column form with a section rail; `preview` renders
# the on-demand drawer from the in-flight form params. Posting is non-custodial (the browser signs +
# broadcasts the kind-30402 request with the consumer's key), so there is no create POST.
class RequestsController < ApplicationController
	include PublishesInBrowser
	include RedirectsOnError

	before_action :require_login
	before_action :set_compose_context, only: %i[new edit]

	# Fields the form posts to #preview; shape the draft. The shared CARRY_KEYS come from PublishesInBrowser.
	PREVIEW_KEYS = %i[title description capability budget delivery_value delivery_unit claim_value claim_unit].freeze

	# "My requests" folded into the unified order hub's Buying tab; this just redirects (the composer below
	# stays at /requests/new + /requests/edit). Kept as a controller action so require_login still applies.
	def index
		redirect_to orders_path(tab: "buying")
	end

	def new
		@draft = Requests::Draft.open_request({}, pubkey: @pubkey)
	end

	# Prefill the form from the poster's own conforming request, keyed on the STABLE d-tag (so edit links
	# survive a re-publish, which recreates the row with a new UUID). A miss (gone/superseded/not theirs/now
	# a listing at that d) raises NotFoundError -> RedirectsOnError sends them back to My requests.
	def edit
		@draft = Requests::FindOwnRequest.call(pubkey: current_user.pubkey, d_tag: params[:d])
		@d_tag = @draft.identifier
	end

	# On-demand preview: builds a draft OpenRequest from the in-flight form and renders the very component
	# the board uses, swapped into the turbo frame inside the preview drawer.
	def preview
		draft = Requests::Draft.open_request(draft_params, pubkey: current_user.pubkey)
		render partial: "requests/preview", locals: { request: draft }
	end

	private

	# Request edits/publishes belong to the consumer's Buying activity, so a recoverable error lands on the
	# orders hub's Buying tab (directly, not via the /requests redirect).
	def error_redirect_fallback
		orders_path(tab: "buying")
	end

	def draft_params = preview_params(*PREVIEW_KEYS)
end
