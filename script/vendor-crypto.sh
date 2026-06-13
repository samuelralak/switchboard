#!/usr/bin/env bash
# Rebuild the vendored, self-contained crypto bundles in vendor/javascript.
#
# Why: nostr-tools (key handling) and @cashu/cashu-ts (escrow locking) must NOT load from a third-party
# CDN -- a jsdelivr compromise would exfiltrate the user's nsec or redirect locked sats and defeat the
# non-custodial invariant. The CDN +esm builds also re-fetch the @noble/@scure chain at runtime, which
# `importmap --download` cannot self-host. This builds one self-contained esbuild bundle per entry point
# (all deps inlined, zero external imports), so config/importmap.rb pins local files and CSP script-src
# stays 'self'. Run this and commit the regenerated vendor/javascript/*.js when bumping a version; keep
# the versions below in sync with the `# @x.y.z vendored` comments in config/importmap.rb.
set -euo pipefail

NOSTR_TOOLS_VERSION="2.23.5"
CASHU_TS_VERSION="4.5.1"
ESBUILD_VERSION="0.24.2"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/vendor/javascript"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

echo "Building vendored crypto in $BUILD"
cd "$BUILD"
npm init -y >/dev/null 2>&1
npm install --no-audit --no-fund \
  "nostr-tools@${NOSTR_TOOLS_VERSION}" \
  "@cashu/cashu-ts@${CASHU_TS_VERSION}" \
  "esbuild@${ESBUILD_VERSION}" >/dev/null
mkdir -p entries out

bundle() { # outfile-stem  module-specifier
  printf 'export * from "%s";\n' "$2" >"entries/$1.js"
  npx esbuild "entries/$1.js" --bundle --format=esm --platform=browser \
    --target=es2020 --minify --legal-comments=none --outfile="out/$1.js"
}

bundle "nostr-tools--pure"  "nostr-tools/pure"
bundle "nostr-tools--nip44" "nostr-tools/nip44"
bundle "nostr-tools--nip19" "nostr-tools/nip19"
bundle "nostr-tools--nip46" "nostr-tools/nip46"
bundle "nostr-tools--nip49" "nostr-tools/nip49"
bundle "nostr-tools--relay" "nostr-tools/relay"
bundle "@cashu--cashu-ts"   "@cashu/cashu-ts"

# Fail closed if any bundle still references a CDN or an unresolved external import.
if grep -lE "jsdelivr|//cdn\.|unpkg|esm\.sh" out/* >/dev/null 2>&1; then
  echo "ERROR: a bundle still references a CDN" >&2; exit 1
fi
if grep -hoE '(from|import)"[^"]+"' out/* | grep -q .; then
  echo "ERROR: a bundle still has an external import (not self-contained)" >&2; exit 1
fi

cp out/*.js "$VENDOR/"
echo "Vendored into $VENDOR:"
ls -1 "$VENDOR"/nostr-tools--*.js "$VENDOR/@cashu--cashu-ts.js"
