import { NsecSigner, Nip07Signer, Nip46Signer } from "nostr/signer"
import { unwrap, UnwrapError, Kind, buildRumor, seal, giftWrap, wrapMessage } from "nostr/nip17"
import { eventId } from "nostr/canonical"
import { RelaySet } from "nostr/relay_set"
import { DmClient, canMessage } from "nostr/dm_client"
import { installMockRelays } from "nostr/mock_relay"
import { buildEvents, broadcastListing, setListingStatus } from "nostr/listing_publish"
import { saveNsec, nsecFor, savedNsecEntry } from "nostr/signer_store"

// Test-only bridge. System tests drive the keyless crypto from an executeScript context, where a
// bare-specifier dynamic import does NOT consult the page import map. Loading THIS module via a real
// <script type="module"> (whose imports DO resolve through the import map, exactly like the shipped
// app) exposes the functions on window so the test can call them. Pinned but never loaded in
// production (nothing imports it; only the system test injects it).
window.NostrCryptoTest = {
  NsecSigner, Nip07Signer, Nip46Signer,
  unwrap, UnwrapError, Kind, eventId, buildRumor, seal, giftWrap, wrapMessage,
  RelaySet, DmClient, canMessage, installMockRelays,
  buildEvents, broadcastListing, setListingStatus,
  saveNsec, nsecFor, savedNsecEntry,
}
