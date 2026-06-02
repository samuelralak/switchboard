# frozen_string_literal: true

module Layout
  module IdentityMenu
    class IdentityMenuComponentPreview < ViewComponent::Preview
      def default
        render(Layout::IdentityMenu::IdentityMenuComponent.new)
      end

      def remote_signer
        render(Layout::IdentityMenu::IdentityMenuComponent.new(npub: "npub1apollo7x9q00000abcd",
                                                               signer: "nip-46 remote"))
      end
    end
  end
end
