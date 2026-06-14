# frozen_string_literal: true

module Orders
	module LedgerRow
		# Previews the consumer ledger row in its two telling states: awaiting funding (the actionable deadline
		# reads in copper) and a settled order. Renders the real row so the meta line + price column verify.
		class LedgerRowComponentPreview < ViewComponent::Preview
			def awaiting
				render(LedgerRowComponent.new(row: Orders::Ledger::Row.new(**attrs(Orders::States::AWAITING_FUNDING))))
			end

			def settled
				render(LedgerRowComponent.new(row: Orders::Ledger::Row.new(**attrs(Orders::States::RELEASED, delivered: true))))
			end

			private

			def attrs(state, delivered: false)
				{
					id: "a1b2c3d4e5f6", title: "Translate a 2,000-word article", cap: "translation",
					sats: 1500, state:, delivered:, created_at: 3.hours.ago, funding_deadline_at: 2.hours.from_now
				}
			end
		end
	end
end
