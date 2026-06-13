# frozen_string_literal: true

module Layout
	module Sidebar
		# The application sidebar: brand, primary navigation, a relay group (capped, with a manage modal),
		# and static footer links pinned to the bottom. Settings now lives in the identity menu, so it is not
		# duplicated here. Provider studio is reached from the top-bar CTA, not here.
		class SidebarComponent < ApplicationComponent
			include RelaysHelper

			# Footer destinations, mostly off-app: the public repo, a Nostr contact profile (via njump), and the
			# in-app legal + donation pages. njump.me is a web gateway that renders a Nostr npub for non-Nostr users.
			CONTACT_NPUB = "npub18rl8k26jzhjq572k3ys93z6csmtzz7jr2uxz3s9r9cmtzg3wjq0q4z92mq"
			REPO_URL     = "https://github.com/samuelralak/switchboard"

			def nav_items
				[
					{ label: "Catalog", href: helpers.root_path, icon: "hgi-store-01", active: on_catalog? },
					{ label: "Orders", href: helpers.orders_path, icon: "hgi-package", active: on_orders? }
				]
			end

			# The first few relays shown inline; the rest are reachable through the manage modal.
			def sidebar_relays = display_relays.first(SIDEBAR_RELAY_CAP)

			def more_relays_count = [ display_relays.length - SIDEBAR_RELAY_CAP, 0 ].max

			# Static links pinned to the bottom of the sidebar. external: opens off-app in a new tab.
			def footer_links
				[
					{ label: "GitHub", href: REPO_URL, icon: "hgi-github-01", external: true },
					{ label: "Contact", href: "https://njump.me/#{CONTACT_NPUB}", icon: "hgi-mail-01", external: true },
					{ label: "Terms & privacy", href: helpers.terms_path, icon: "hgi-legal-document-01", external: false },
					{ label: "Donate", href: helpers.donate_path, icon: "hgi-favourite", external: false }
				]
			end

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
		end
	end
end
