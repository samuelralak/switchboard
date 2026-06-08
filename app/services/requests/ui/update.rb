# frozen_string_literal: true

module Requests
	module Ui
		# Broadcasts an open-request update to every open board for the event's coordinate (the demand-side
		# mirror of Catalog::Ui::Update). A withdrawn/inactive (or claimed/expired) version is remove-only
		# (mirrors Requests::Search's status filter). The card+drawer plumbing lives in Shared::CardBroadcast.
		class Update
			def self.call(event:)
				card = State.card(event:)
				Shared::CardBroadcast.call(card:, visible: card.request.open?)
			end
		end
	end
end
