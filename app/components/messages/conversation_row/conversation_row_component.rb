# frozen_string_literal: true

module Messages
	module ConversationRow
		# One request in the inbox list, mirroring the "My requests" ledger row: id,
		# service, state chip, deadline, and price. Links to its thread; `selected`
		# highlights the open one.
		class ConversationRowComponent < ApplicationComponent
			attr_reader :conversation

			def initialize(conversation:, selected: false)
				@conversation = conversation
				@selected = selected
			end

			def selected? = @selected
		end
	end
end
