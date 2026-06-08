# frozen_string_literal: true

module Catalog
	module Ui
		# Broadcasts a listing update to every open catalog for the event's coordinate. An unpublished/inactive
		# version is remove-only (re-adding would undo the unpublish for every open catalog; mirrors
		# Catalog::Search's status filter). The card+drawer plumbing lives in Shared::CardBroadcast.
		class Update
			def self.call(event:)
				card = State.card(event:)
				Shared::CardBroadcast.call(card:, visible: card.listing.active?)
			end
		end
	end
end
