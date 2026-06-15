# frozen_string_literal: true

# Shared resolver for a viewer's chosen catalog view (cookie > saved account default > operator default), so
# the catalog and the Settings chooser cannot drift. Each tier is validated against Attestation::VIEWS, so a
# stale cookie falls through instead of collapsing to the default. Cookie-first so a failed account PATCH never
# reverts the viewer. Callers force "all" when attestation is off.
module ResolvesCatalogView
	extend ActiveSupport::Concern

	private

	def resolved_catalog_view
		[ cookies[:catalog_view], current_user&.catalog_view ].find { |view| Attestation::VIEWS.include?(view) } ||
			Attestation::Policy.default_view
	end
end
