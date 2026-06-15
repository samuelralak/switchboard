# frozen_string_literal: true

module Catalog
	module Ui
		# Broadcasts a listing update to every open catalog for the event's coordinate. An unpublished/inactive
		# version (or an operator-flagged author) is remove-only (re-adding would undo the unpublish/takedown
		# for every open catalog; mirrors Catalog::Search's status + not_from_flagged filters). visible: false
		# forces remove-only (a deleted listing). The card+drawer plumbing lives in Shared::CardBroadcast.
		class Update
			def self.call(event:, visible: nil)
				card = State.card(event:)

				if visible.nil?
					visible = card.listing.active? && !User.flagged?(event.pubkey)
				end

				Shared::CardBroadcast.call(card:, visible:)
			end
		end
	end
end
