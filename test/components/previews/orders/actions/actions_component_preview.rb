# frozen_string_literal: true

module Orders
	module Actions
		# Visual preview of the order action panels (no DB): the provider's deliver form is the focus.
		class ActionsComponentPreview < ViewComponent::Preview
			# The provider's "Submit delivery" form on a funded order.
			def deliver_form
				render(ActionsComponent.new(order: funded_order, viewer: viewer(funded_order.provider_pubkey)))
			end

			private

			def funded_order
				@funded_order ||= Order.new(
					id: "00000000-0000-0000-0000-0000000000d1", current_state: Orders::States::FUNDED,
					entry_point: Orders::EntryPoints::CATALOG_ORDER, provider_pubkey: "a" * 64,
					consumer_pubkey: "b" * 64, mint_url: "http://127.0.0.1:3338",
					listing_coordinate: "30402:#{'a' * 64}:svc", amount_sats: 5_000
				)
			end

			def viewer(pubkey) = Struct.new(:pubkey).new(pubkey)
		end
	end
end
