# frozen_string_literal: true

# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# Tailwind Plus Elements: headless interactive web components (dialog, dropdown,
# tabs, popover, command palette, select, autocomplete, etc.). Vendored in
# vendor/javascript/. Requires a Tailwind Plus license (https://tailwindcss.com/plus).
pin "@tailwindplus/elements", to: "@tailwindplus--elements.js" # @1.0.22

# Sign in with Nostr. NIP-07 (extension) uses window.nostr directly, no JS dependency.
# NIP-46 (bunker) and the pasted-nsec path use nostr-tools, lazy-imported only when used;
# nip49 encrypts a saved key (NIP-49) for localStorage. The +esm bundles rewrite @noble/@scure
# imports to absolute CDN URLs, so no extra pins.
# Vendor before ship: bin/importmap pin nostr-tools/nip46 nostr-tools/nip19 nostr-tools/nip49 --download
pin "nostr-tools/nip46", to: "https://cdn.jsdelivr.net/npm/nostr-tools@2.23.5/nip46/+esm" # @2.23.5
pin "nostr-tools/nip19", to: "https://cdn.jsdelivr.net/npm/nostr-tools@2.23.5/nip19/+esm" # @2.23.5
pin "nostr-tools/nip49", to: "https://cdn.jsdelivr.net/npm/nostr-tools@2.23.5/nip49/+esm" # @2.23.5
pin "nostr-tools/pure", to: "https://cdn.jsdelivr.net/npm/nostr-tools@2.23.5/pure/+esm" # @2.23.5
