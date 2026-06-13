# frozen_string_literal: true

module Requests
	module Ui
		# Broadcasts an open-request update to every open board for the event's coordinate (the demand-side
		# mirror of Catalog::Ui::Update). A withdrawn/inactive/claimed/expired version (or an operator-flagged
		# author) is remove-only (mirrors Requests::Search's status + not_from_flagged filters). visible: false
		# forces remove-only (a deleted request). The card+drawer plumbing lives in Shared::CardBroadcast.
		class Update
			def self.call(event:, visible: nil)
				card = State.card(event:)
				visible = card.request.open? && !User.flagged?(event.pubkey) if visible.nil?
				Shared::CardBroadcast.call(card:, visible:)
			end
		end
	end
end
