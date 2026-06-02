# frozen_string_literal: true

module Layout
  module IdentityMenu
    # The signer-identity menu in the top bar: shows the connected npub and signer
    # status, with a dropdown of account actions. Built on Tailwind Plus Elements
    # (<el-dropdown> / <el-menu>). Wire `npub` / `signer` to real NIP-07/46 auth
    # state once authentication exists.
    class IdentityMenuComponent < ApplicationComponent
      def initialize(npub: "npub1you000000000000000000000000000000000000000000k4m2", signer: "key in signer")
        @npub = npub
        @signer = signer
      end

      attr_reader :signer

      # Compact npub for display: keep the recognizable prefix and suffix.
      def display_npub
        return @npub if @npub.length <= 14

        "#{@npub[0, 8]}…#{@npub[-4..]}"
      end

      def menu_items
        [
          { label: "Your profile",      href: "#" },
          { label: "Your listings",     href: "#" },
          { label: "Disconnect signer", href: "#", separated: true }
        ]
      end
    end
  end
end
