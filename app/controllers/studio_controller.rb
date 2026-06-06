# frozen_string_literal: true

# Provider studio: author, publish, and manage kind-30402 service listings. Session-authenticated.
# Publishing/editing/unpublishing are non-custodial (the browser signs + broadcasts with the provider's
# key, brief §6.3), so there is no create/update/destroy: `index` lists the provider's own listings,
# `new`/`edit` render the single-column authoring form with a section rail (edit prefilled + re-publishing
# under the same d-tag), and `preview` renders the on-demand buyer view from the in-flight form params.
class StudioController < ApplicationController
	before_action :require_login
	before_action :set_studio_context, only: %i[new edit]

	# Fields the form posts to #preview (the on-demand buyer preview). PREVIEW_KEYS shape the draft;
	# CARRY_KEYS carry the existing listing through an edit (d_tag = coordinate; status/published_at/
	# created_at preserved on re-publish). The Draft ignores CARRY_KEYS, but they are permitted so the
	# POST logs no unpermitted params.
	PREVIEW_KEYS = %i[
		title description capability price price_frequency fulfillment endpoint delivery_value delivery_unit
	].freeze
	CARRY_KEYS = %i[d_tag status published_at created_at].freeze

	def index
		@listings = Catalog::ProviderListings.call(pubkey: current_user.pubkey)
	end

	def new
		@draft = Catalog::Draft.listing({}, pubkey: @pubkey)
	end

	# Prefill the form from an existing listing, keyed on the STABLE d-tag (scoped to the provider's own,
	# so they can't edit someone else's). Keying on the d-tag (not the DB row id) keeps edit links valid
	# after a re-publish, which destroys + recreates the row with a new UUID. The form re-publishes under
	# the same d-tag, superseding the current version.
	def edit
		event = Event.classified.find_by(pubkey: current_user.pubkey, d_tag: params[:d].to_s)
		@draft = event && Catalog::Listing.new(event)
		# Gone, superseded, not the provider's own, or the coordinate now holds an open request (requests
		# share kind 30402 and could supersede a listing at the same d): only a conforming listing edits here.
		return redirect_to(studio_path) unless @draft&.conforms?

		@d_tag = @draft.identifier
	end

	# On-demand buyer preview: builds a draft Catalog::Listing from the in-flight form and renders the very
	# component the catalog uses, swapped into the turbo frame inside the preview drawer.
	def preview
		draft = Catalog::Draft.listing(draft_params, pubkey: current_user.pubkey)
		render partial: "studio/preview", locals: { listing: draft }
	end

	private

	def set_studio_context
		@pubkey = current_user.pubkey
		@publish_relays = NostrClient.configuration.relays # the catalog ingest relays; publish there so it is catalogued
		@btc_usd = Pricing::BtcRate.call # nil hides the fiat hint; never blocks the render
	end

	def draft_params
		# Drop the framework CSRF token before the top-level permit (it is still verified by Rails before
		# this action runs); otherwise it logs as an unpermitted parameter on every preview POST.
		fields = params.except(:authenticity_token)
		fields.permit(*PREVIEW_KEYS, *CARRY_KEYS, images: %i[url m x dim], schema: %i[name label type required]).to_h
	end
end
