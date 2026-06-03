# frozen_string_literal: true

module Catalog
	module Ui
		# Broadcasts a listing update to every open catalog for the event's coordinate.
		class Update
			def self.call(event:)
				ui = State.card(event:)

				Turbo::StreamsChannel.broadcast_remove_to(
					ui.stream,
					target: ui.card_id
				)

				Turbo::StreamsChannel.broadcast_prepend_to(
					ui.stream,
					target: ui.grid_target,
					partial: ui.partial,
					locals: ui.locals
				)
			end
		end
	end
end
