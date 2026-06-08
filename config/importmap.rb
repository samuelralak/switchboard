# frozen_string_literal: true

# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
# Keyless NIP-17 client crypto (#32): canonical id, nip44 wrapper, signer adapter, seal/wrap/unwrap.
pin_all_from "app/javascript/nostr", under: "nostr"

# Tailwind Plus Elements: headless interactive web components (dialog, dropdown,
# tabs, popover, command palette, select, autocomplete, etc.). Vendored in
# vendor/javascript/. Requires a Tailwind Plus license (https://tailwindcss.com/plus).
pin "@tailwindplus/elements", to: "@tailwindplus--elements.js" # @1.0.22

# Sign in with Nostr. NIP-07 (extension) uses window.nostr directly, no JS dependency.
# NIP-46 (bunker) and the pasted-nsec path use nostr-tools, lazy-imported only when used;
# nip49 encrypts a saved key (NIP-49) for localStorage. The +esm bundles rewrite @noble/@scure
# imports to absolute CDN URLs, so no extra pins.
# Vendor before ship: bin/importmap pin nostr-tools/nip46 nostr-tools/nip19 nostr-tools/nip49 nostr-tools/nip44 nostr-tools/relay --download
pin "nostr-tools/nip46", to: "https://cdn.jsdelivr.net/npm/nostr-tools@2.23.5/nip46/+esm" # @2.23.5
pin "nostr-tools/nip19", to: "https://cdn.jsdelivr.net/npm/nostr-tools@2.23.5/nip19/+esm" # @2.23.5
pin "nostr-tools/nip49", to: "https://cdn.jsdelivr.net/npm/nostr-tools@2.23.5/nip49/+esm" # @2.23.5
pin "nostr-tools/pure", to: "https://cdn.jsdelivr.net/npm/nostr-tools@2.23.5/pure/+esm" # @2.23.5
# NIP-44 v2 (seal/wrap encryption) + the low-level Relay transport (#32 browser client; the Relay
# hands a kind-22242 template to our user signer for NIP-42 AUTH and never sees a key).
pin "nostr-tools/nip44", to: "https://cdn.jsdelivr.net/npm/nostr-tools@2.23.5/nip44/+esm" # @2.23.5
pin "nostr-tools/relay", to: "https://cdn.jsdelivr.net/npm/nostr-tools@2.23.5/relay/+esm" # @2.23.5

# Cashu (NUT-11 P2PK / NUT-14 HTLC) for non-custodial manual-order escrow: the browser builds the
# key-locked / hash-locked token; the runtime never holds it. Pinned at an exact version because v4
# renamed CashuWallet->Wallet / CashuMint->Mint and SIG_ALL is still in flux (we use SIG_INPUTS).
# Same vendoring caveat as nostr-tools: the +esm bundle bakes absolute jsdelivr URLs for the
# @noble/@scure/@cashu chain, so --download won't fully self-host; CSP allows cdn.jsdelivr.net.
pin "@cashu/cashu-ts", to: "https://cdn.jsdelivr.net/npm/@cashu/cashu-ts@4.5.1/+esm" # @4.5.1
