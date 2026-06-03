# frozen_string_literal: true

class PagesController < ApplicationController
	def home
		@catalog = Catalog::Ui::State.grid(query: search_query)
	end

	private

	def search_query
		query = params[:q]
		query = params[:search][:q] if query.blank? && params[:search].is_a?(ActionController::Parameters)
		query.to_s.strip
	end
end
