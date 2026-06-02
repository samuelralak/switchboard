# frozen_string_literal: true

module Layout
  module Sidebar
    # The application sidebar: brand, primary navigation, and relay status.
    # Rendered in both the mobile slide-over and the static desktop sidebar, so it
    # is a single source of truth for the navigation chrome.
    class SidebarComponent < ApplicationComponent
      def nav_items
        [
          { label: "Catalog",         href: helpers.root_path, icon: "hgi-store-01",     active: on_catalog? },
          { label: "My requests",     href: "#",               icon: "hgi-package",      active: false },
          { label: "Provider studio", href: "#",               icon: "hgi-store-add-01", active: false }
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

      # Catalog is the landing page; highlight it when we are on root. Guarded so it
      # is safe to render outside a request (for example in component previews).
      def on_catalog?
        helpers.current_page?(helpers.root_path)
      rescue StandardError
        false
      end
    end
  end
end
