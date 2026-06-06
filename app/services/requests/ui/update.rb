# frozen_string_literal: true

module Requests
	module Ui
		# Broadcasts an open-request update to every open board for the event's coordinate. The demand-side
		# mirror of Catalog::Ui::Update.
		class Update
			def self.call(event:)
				card = State.card(event:)
				remove_stale(card)
				# A withdrawn/inactive (or claimed/expired) version is remove-only: re-adding it would undo the
				# withdrawal for every open board. Mirrors Requests::Search's status filter (open? = status tag).
				add(card) if card.request.open?
			end

			# Drop the stale card + its drawer, so an edit/withdrawal does not leave duplicates.
			def self.remove_stale(card)
				channel = Turbo::StreamsChannel
				channel.broadcast_remove_to(card.stream, target: card.card_id)
				channel.broadcast_remove_to(card.stream, target: card.drawer_id)
			end

			# Re-add the card AND its drawer, so the live-prepended card is openable (not a dead button).
			def self.add(card)
				channel = Turbo::StreamsChannel
				stream = card.stream
				locals = card.locals
				channel.broadcast_prepend_to(stream, target: card.grid_target, partial: card.partial, locals:)
				channel.broadcast_append_to(stream, target: card.drawer_target, partial: card.drawer_partial, locals:)
			end

			private_class_method :remove_stale, :add
		end
	end
end
