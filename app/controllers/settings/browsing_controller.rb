# frozen_string_literal: true

module Settings
	# The viewer's catalog-view preference (all vs platform-verified). show renders the chooser; update saves it
	# onto the User projection as the account default. The on-catalog filter PATCHes the same action (as JSON) so
	# a signed-in viewer's quick toggle and their saved default stay one value. Anonymous viewers keep the choice
	# in a cookie (no account row), so this is login-gated like the rest of Settings.
	class BrowsingController < ApplicationController
		before_action :require_login

		def show
			# Effective choice (cookie > account > default), so the chooser never disagrees with the catalog.
			@catalog_view = resolved_catalog_view
			@attestation_enabled = Attestation::Policy.enabled?
		end

		def update
			view = params.expect(:catalog_view)
			return reject_view unless Attestation::VIEWS.include?(view)

			current_user.update!(catalog_view: view)
			# Keep the cookie in lockstep (it wins in the resolver) so this device reflects the change at once.
			cookies[:catalog_view] = { value: view, expires: 1.year, same_site: :lax, secure: Rails.env.production? }

			respond_to do |format|
				format.json { head :no_content }
				format.html { redirect_to settings_browsing_path, notice: "Saved. Your catalog now defaults to #{view}." }
			end
		end

		private

		def reject_view
			respond_to do |format|
				format.json { head :unprocessable_content }
				format.html { redirect_to settings_browsing_path, alert: "Unknown catalog view." }
			end
		end
	end
end
