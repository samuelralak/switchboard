# frozen_string_literal: true

# A provider's public profile = their portfolio: identity projected from kind-0 + their published services.
# Viewer-aware (the owner additionally gets manage controls). Public, npub-keyed so it is shareable. A valid
# but not-yet-ingested npub triggers a background kind-0 fetch and renders a placeholder rather than 404ing
# (the pubkey is real even if we have not projected its profile); only a malformed/non-npub identifier 404s.
class ProfilesController < ApplicationController
	def show
		@pubkey = User.pubkey_from_npub(params[:npub]) or raise ActiveRecord::RecordNotFound

		@user = User.find_by(pubkey: @pubkey)
		@is_owner = current_user&.pubkey == @pubkey
		@listings = @user ? Catalog::ProviderListings.call(pubkey: @pubkey) : []

		return if @user

		Users::MetadataFetchJob.perform_later(@pubkey, force: true)
	end
end
