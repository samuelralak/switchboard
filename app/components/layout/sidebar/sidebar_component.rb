# frozen_string_literal: true

module Layout
	module Sidebar
		# The application sidebar: brand, primary navigation, a relay group (capped, with a manage modal),
		# and a settings link pinned to the bottom. Provider studio is reached from the top-bar CTA, not here.
		class SidebarComponent < ApplicationComponent
			include RelaysHelper

			def nav_items
				[
					{ label: "Catalog", href: helpers.root_path, icon: "hgi-store-01", active: on_catalog? },
					{ label: "Orders", href: helpers.orders_path, icon: "hgi-package", active: on_orders? }
				]
			end

			# The first few relays shown inline; the rest are reachable through the manage modal.
			def sidebar_relays = display_relays.first(SIDEBAR_RELAY_CAP)

			def more_relays_count = [ display_relays.length - SIDEBAR_RELAY_CAP, 0 ].max

			private

			# True when the current page is root. False outside a request.
			def on_catalog?
				helpers.current_page?(helpers.root_path)
			rescue StandardError
				false
			end

			# True across the order hub and its sub-flows: the hub itself, the request composer (/requests/new),
			# and an order's message thread (/messages/:id) -- all "your orders" surfaces. False outside a request.
			def on_orders?
				helpers.request.path.start_with?("/orders", "/requests", "/messages")
			rescue StandardError
				false
			end

			# True anywhere under settings (the section rail's sub-pages). False outside a request.
			def on_settings?
				helpers.request.path.start_with?("/settings")
			rescue StandardError
				false
			end
		end
	end
end
