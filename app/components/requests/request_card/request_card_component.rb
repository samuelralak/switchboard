# frozen_string_literal: true

module Requests
	module RequestCard
		# An open request as a horizontal list card: a copper-tinted lead slot marks it as demand (no images,
		# unlike a listing), the title with an "open" pill, capability + the poster, an optional one-line
		# brief, and the funded budget. The whole row opens the request drawer. Mirrors the catalog list card
		# and emits the same data-* contract so the shared catalog Stimulus controller filters + sorts it.
		class RequestCardComponent < ApplicationComponent
			attr_reader :request

			def initialize(request:)
				@request = request
			end

			delegate :title, :description, :summary, :capability, :poster_npub, :dom_id, :image,
							:budget?, :budget_amount, :budget_currency, :claim_window, :search_text, to: :request

			def blurb = description.presence || summary

			# Sort keys for the reused catalog toolbar: integer sats budget (0 when unset) and the unix ts.
			def budget_value = budget_amount.to_i
			def created_at = request.event.nostr_created_at.to_i
		end
	end
end
