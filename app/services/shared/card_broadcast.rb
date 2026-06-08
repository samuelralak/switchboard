# frozen_string_literal: true

module Shared
	# The live card+drawer broadcast shared by the catalog and the open-request board: drop the stale card +
	# its drawer, then (only when the card is still `visible`) re-prepend the card and re-append its drawer, so
	# an edit/unpublish never leaves a duplicate or a dead (button without a drawer) card. `card` is the
	# domain's Ui::State.card value object, duck-typed: stream / card_id / drawer_id / grid_target / partial /
	# drawer_target / drawer_partial / locals.
	class CardBroadcast < BaseService
		option :card
		option :visible, type: Types::Strict::Bool

		def call
			remove_stale
			add if visible
		end

		private

		def remove_stale
			channel.broadcast_remove_to(card.stream, target: card.card_id)
			channel.broadcast_remove_to(card.stream, target: card.drawer_id)
		end

		def add
			stream = card.stream
			locals = card.locals
			channel.broadcast_prepend_to(stream, target: card.grid_target, partial: card.partial, locals:)
			channel.broadcast_append_to(stream, target: card.drawer_target, partial: card.drawer_partial, locals:)
		end

		def channel = Turbo::StreamsChannel
	end
end
