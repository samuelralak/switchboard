# frozen_string_literal: true

module Orders
	module Lifecycle
		# Visual preview of the lifecycle stepper across states (no DB; timestamps/countdowns need a persisted
		# order, but the strip + node timeline + lamps render).
		class LifecycleComponentPreview < ViewComponent::Preview
			def awaiting_funding = render(LifecycleComponent.new(order: order(Orders::States::AWAITING_FUNDING)))
			def funded = render(LifecycleComponent.new(order: order(Orders::States::FUNDED)))
			def released = render(LifecycleComponent.new(order: order(Orders::States::RELEASED)))

			private

			def order(state)
				Order.new(
					id: "00000000-0000-0000-0000-0000000000c#{Orders::States::ALL.index(state)}",
					current_state: state, entry_point: Orders::EntryPoints::CATALOG_ORDER,
					provider_pubkey: "a" * 64, consumer_pubkey: "b" * 64, mint_url: "http://127.0.0.1:3338",
					listing_coordinate: "30402:#{'a' * 64}:svc", amount_sats: 5_000, created_at: 2.hours.ago
				)
			end
		end
	end
end
