# frozen_string_literal: true

module Orders
	# Visual preview of the assembled order-detail body (the drawer's lazy-frame content): the escrow card,
	# the parties/mint, the consumer's request + release actions, and the delivered-result panel. Uses an
	# in-memory order + viewer so the whole composition can be eyeballed without a session.
	class DetailPreview < ViewComponent::Preview
		# layout false: render the bare body, not the app chrome.
		def funded_consumer
			render_with_template(locals: { order: fixture(Orders::States::FUNDED), viewer: viewer })
		end

		def awaiting_consumer
			render_with_template(
				template: "orders/detail_preview/funded_consumer",
				locals: { order: fixture(Orders::States::AWAITING_FUNDING), viewer: viewer }
			)
		end

		private

		def viewer = User.new(pubkey: "b" * 64)

		def fixture(state)
			Order.new(
				id: "00000000-0000-0000-0000-00000000d00#{Orders::States::ALL.index(state)}",
				current_state: state, entry_point: Orders::EntryPoints::CATALOG_ORDER,
				provider_pubkey: "a" * 64, consumer_pubkey: "b" * 64,
				mint_url: "https://mint.minibits.cash/Bitcoin", listing_coordinate: "30402:#{'a' * 64}:svc",
				amount_sats: 5_000, created_at: 2.hours.ago, funding_deadline_at: 20.hours.from_now
			)
		end
	end
end
