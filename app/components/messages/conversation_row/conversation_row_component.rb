# frozen_string_literal: true

module Messages
	module ConversationRow
		# One order in a provider's list: service, state chip, peer, and price. The link target is passed in
		# (`href`) so the same row serves two contexts -- the orders hub (selects in the right pane) and the
		# standalone thread page (switches threads). `selected` highlights the open one.
		class ConversationRowComponent < ApplicationComponent
			attr_reader :conversation, :href

			def initialize(conversation:, href:, selected: false)
				@conversation = conversation
				@href = href
				@selected = selected
			end

			def selected?
				@selected
			end
		end
	end
end
