# frozen_string_literal: true

class PagesController < ApplicationController
	def home
		# Two lenses over one search: services (supply) and open requests (demand), browsed via tabs.
		@catalog = Catalog::Ui::State.grid(query: search_query)
		@board = Requests::Ui::State.grid(query: search_query)

		# Attestation as a per-viewer filter (all vs verified-only): shown only when the feature is on; the
		# initial view is the viewer's saved/cookied choice, else the operator default, and "all" (no filter)
		# when the feature is off.
		@attestation_filter = Attestation::Policy.enabled?
		@catalog_view = @attestation_filter ? resolved_catalog_view : "all"
	end

	# `terms` and `donate` are static pages with no data, so they have no action method: Rails renders
	# pages/terms.html.erb and pages/donate.html.erb implicitly from the route.

	private

	def search_query
		query = params[:q]
		query = params[:search][:q] if query.blank? && params[:search].is_a?(ActionController::Parameters)
		query.to_s.strip
	end
end
