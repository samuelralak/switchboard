# frozen_string_literal: true

module Requests
	module Ui
		# Render state for the open-request board, shared by the page render and the live broadcast so both
		# use the same stream, grid target, and partial. Mirrors Catalog::Ui::State on the demand side.
		class State
			STREAM         = "open_requests"
			GRID_TARGET    = "open_request_list"
			PARTIAL        = "requests/request"
			# The container the live broadcast appends a card's drawer into.
			DRAWER_TARGET  = "request-drawers"
			DRAWER_PARTIAL = "requests/drawer"

			# One request card (+ its drawer), broadcast by Requests::Ui::Update.
			Card = Data.define(:request, :stream, :grid_target, :partial) do
				def card_id = request.dom_id
				# The removable drawer wrapper id (see requests/_drawer.html.erb).
				def drawer_id = "request-drawer-#{request.dom_id}-wrap"
				def drawer_target = DRAWER_TARGET
				def drawer_partial = DRAWER_PARTIAL
				def locals = { request: }
			end

			# The board for the page render.
			Grid = Data.define(:requests, :query, :stream, :grid_target, :partial) do
				delegate :size, to: :requests
				def never_posted? = requests.empty? && query.blank?
				def no_matches? = requests.empty? && query.present?
			end

			def self.card(event:)
				Card.new(
					request: OpenRequest.new(event),
					stream: STREAM,
					grid_target: GRID_TARGET,
					partial: PARTIAL
				)
			end

			# pubkey set narrows to one poster's own requests (the My-requests page); nil = the public board.
			def self.grid(query: nil, pubkey: nil)
				Grid.new(
					requests: Requests::Search.call(query:, pubkey:),
					query:,
					stream: STREAM,
					grid_target: GRID_TARGET,
					partial: PARTIAL
				)
			end
		end
	end
end
