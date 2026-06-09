# frozen_string_literal: true

module Requests
	module MyRequest
		# One row in My-requests' posted-requests list: cover, title, status, budget + capability + claim
		# window, with an Edit link and a Withdraw/Re-post toggle. The toggle re-signs the existing event with
		# the status tag flipped (preserving all data, reversible); `payload` carries that event to the
		# my_requests controller. Mirrors Studio::MyListing::MyListingComponent on the demand side.
		class MyRequestComponent < ApplicationComponent
			attr_reader :request

			def initialize(request:)
				@request = request
			end

			delegate :title, :open?, :image, :capability, :identifier, to: :request
			delegate :budget?, :budget_amount, :budget_currency, :claim_window, to: :request

			def next_status = open? ? "inactive" : "active"
			def toggle_label = open? ? "Withdraw" : "Re-post"
			def status_label = open? ? "open" : "withdrawn"
			def status_tone = open? ? "text-lamp-settled" : "text-ink-faint"

			# The event the status toggle re-signs (kind + content + tags + created_at, so the re-sign can
			# supersede with a monotonic created_at), as JSON for the data param.
			def payload
				{ kind: request.event.kind, content: request.event.content, tags: request.event.tags,
					created_at: request.event.nostr_created_at&.to_i }.to_json
			end
		end
	end
end
