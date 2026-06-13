# frozen_string_literal: true

# Provider studio: author, publish, and manage kind-30402 service listings. Session-authenticated.
# Publishing/editing/unpublishing are non-custodial (the browser signs + broadcasts with the provider's
# key, brief §6.3), so there is no create/update/destroy: `index` lists the provider's own listings,
# `new`/`edit` render the single-column authoring form with a section rail (edit prefilled + re-publishing
# under the same d-tag), and `preview` renders the on-demand buyer view from the in-flight form params.
class StudioController < ApplicationController
	include PublishesInBrowser
	include RedirectsOnError

	before_action :require_login
	before_action :set_compose_context, only: %i[new edit]

	# Fields the form posts to #preview (the on-demand buyer preview); shape the draft. The shared
	# CARRY_KEYS (the edit coordinate + NIP-99 status/timestamps) come from PublishesInBrowser.
	PREVIEW_KEYS = %i[
		title description capability price price_frequency fulfillment endpoint delivery_value delivery_unit
	].freeze

	# Managing your listings now lives on your profile (the portfolio surface). The route + name stay so the
	# redirect and any old links resolve; the authoring form is reached via the "Provider studio" CTA -> new.
	def index
		redirect_to profile_path(npub: current_user.npub), status: :see_other
	end

	def new
		@draft = Catalog::Draft.listing({}, pubkey: @pubkey)
	end

	# Prefill the form from the provider's own conforming listing, keyed on the STABLE d-tag (so edit links
	# survive a re-publish, which recreates the row with a new UUID). A miss (gone/superseded/not theirs/now
	# an open request at that d) raises NotFoundError -> RedirectsOnError sends them back to the studio.
	def edit
		@draft = Catalog::FindOwnListing.call(pubkey: current_user.pubkey, d_tag: params[:d])
		@d_tag = @draft.identifier
	end

	# On-demand buyer preview: builds a draft Catalog::Listing from the in-flight form and renders the very
	# component the catalog uses, swapped into the turbo frame inside the preview drawer.
	def preview
		draft = Catalog::Draft.listing(draft_params, pubkey: current_user.pubkey)
		render partial: "studio/preview", locals: { listing: draft }
	end

	private

	# A recoverable edit/publish error lands the provider on their profile, which now hosts manage.
	def error_redirect_fallback = profile_path(npub: current_user.npub)

	def draft_params
		preview_params(*PREVIEW_KEYS, { images: %i[url m x dim], schema: %i[name label type required] })
	end
end
