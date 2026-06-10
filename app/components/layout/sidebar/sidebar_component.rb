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
					{ label: "My requests", href: helpers.requests_path, icon: "hgi-package", active: on_requests? },
					{ label: "Messages", href: helpers.messages_path, icon: "hgi-mail-01", active: on_messages? }
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

			# True anywhere under My requests / the request composer. False outside a request.
			def on_requests?
				helpers.request.path.start_with?("/requests")
			rescue StandardError
				false
			end

			# True anywhere under the messages inbox. False outside a request.
			def on_messages?
				helpers.request.path.start_with?("/messages")
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
