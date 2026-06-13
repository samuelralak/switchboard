# frozen_string_literal: true

# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
# Keyless NIP-17 client crypto (#32): canonical id, nip44 wrapper, signer adapter, seal/wrap/unwrap.
pin_all_from "app/javascript/nostr", under: "nostr"
# Test-only crypto/relay bridges (keyless-signer fake, NIP-44 vectors, mock relays), injected by the system
# test harness via imports["nostr/test_support"]. Kept under the same nostr/ module names but pinned ONLY
# outside production, so the money app never serves test crypto same-origin. Explicit pins (a second
# pin_all_from under the same namespace registers nothing).
unless Rails.env.production?
	pin "nostr/test_support", to: "test_support/test_support.js"
	pin "nostr/mock_relay", to: "test_support/mock_relay.js"
	pin "nostr/cashu_test_support", to: "test_support/cashu_test_support.js"
end

# Tailwind Plus Elements: headless interactive web components (dialog, dropdown,
# tabs, popover, command palette, select, autocomplete, etc.). Vendored in
# vendor/javascript/. Requires a Tailwind Plus license (https://tailwindcss.com/plus).
pin "@tailwindplus/elements", to: "@tailwindplus--elements.js" # @1.0.22

# Sign in with Nostr. NIP-07 (extension) uses window.nostr directly, no JS dependency.
# NIP-46 (bunker) and the pasted-nsec path use nostr-tools, lazy-imported only when used;
# nip49 encrypts a saved key (NIP-49) for localStorage.
# VENDORED, not CDN: this code handles the user's nsec and builds the Cashu escrow lock, so it must
# never load from a third-party CDN (a jsdelivr compromise would exfiltrate keys / redirect locked sats
# and defeat the non-custodial invariant). Each pin is a self-contained esbuild bundle with the whole
# @noble/@scure/@cashu chain inlined (zero external imports, so script-src stays 'self'), built from the
# exact pinned version into vendor/javascript by script/vendor-crypto.sh -- rerun it to bump a version.
pin "nostr-tools/nip46", to: "nostr-tools--nip46.js" # @2.23.5 vendored
pin "nostr-tools/nip19", to: "nostr-tools--nip19.js" # @2.23.5 vendored
pin "nostr-tools/nip49", to: "nostr-tools--nip49.js" # @2.23.5 vendored
pin "nostr-tools/pure", to: "nostr-tools--pure.js" # @2.23.5 vendored
# NIP-44 v2 (seal/wrap encryption) + the low-level Relay transport (#32 browser client; the Relay
# hands a kind-22242 template to our user signer for NIP-42 AUTH and never sees a key).
pin "nostr-tools/nip44", to: "nostr-tools--nip44.js" # @2.23.5 vendored
pin "nostr-tools/relay", to: "nostr-tools--relay.js" # @2.23.5 vendored

# Cashu (NUT-11 P2PK / NUT-14 HTLC) for non-custodial manual-order escrow: the browser builds the
# key-locked / hash-locked token; the runtime never holds it. Pinned at an exact version because v4
# renamed CashuWallet->Wallet / CashuMint->Mint and SIG_ALL is still in flux (we use SIG_INPUTS).
# Vendored self-contained (see above) so the escrow-locking code never loads from a CDN.
pin "@cashu/cashu-ts", to: "@cashu--cashu-ts.js" # @4.5.1 vendored

# QR rendering for the Lightning funding invoice. Self-hosted (script-src stays 'self'): a convenience lib,
# not crypto, that renders a bolt11 to inline SVG. Vendored as a self-contained esbuild bundle of
# qrcode-generator (a CJS default export): build with
#   echo 'import qr from "qrcode-generator"; export default qr;' > e.js
#   npm i qrcode-generator@1.4.4 esbuild && npx esbuild e.js --bundle --format=esm --platform=browser --minify
pin "qrcode-generator", to: "qrcode-generator.js" # @1.4.4 vendored
