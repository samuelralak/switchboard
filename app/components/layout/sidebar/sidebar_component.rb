# frozen_string_literal: true

module Layout
	module Sidebar
		# The application sidebar: brand, primary navigation, and relay status.
		class SidebarComponent < ApplicationComponent
			def nav_items
				[
					{ label: "Catalog", href: helpers.root_path, icon: "hgi-store-01", active: on_catalog? },
					{ label: "Messages", href: helpers.messages_path, icon: "hgi-mail-01", active: on_messages? },
					{ label: "My requests", href: "#", icon: "hgi-package", active: false },
					{ label: "Provider studio", href: "#", icon: "hgi-store-add-01", active: false }
				]
			end

			def relays
				[
					{ host: "relay.damus.io",   status: :settled },
					{ host: "nos.lol",          status: :settled },
					{ host: "relay.primal.net", status: :settled },
					{ host: "nostr.band",       status: :live }
				]
			end

			private

			# True when the current page is root. False outside a request.
			def on_catalog?
				helpers.current_page?(helpers.root_path)
			rescue StandardError
				false
			end

			# True anywhere under the messages inbox. False outside a request.
			def on_messages?
				helpers.request.path.start_with?("/messages")
			rescue StandardError
				false
			end
		end
	end
end
