import { NsecSigner } from "nostr/signer"
import { unwrap, UnwrapError, Kind, buildRumor, seal, giftWrap, wrapMessage } from "nostr/nip17"
import { eventId } from "nostr/canonical"

// Test-only bridge. System tests drive the keyless crypto from an executeScript context, where a
// bare-specifier dynamic import does NOT consult the page import map. Loading THIS module via a real
// <script type="module"> (whose imports DO resolve through the import map, exactly like the shipped
// app) exposes the functions on window so the test can call them. Pinned but never loaded in
// production (nothing imports it; only the system test injects it).
window.NostrCryptoTest = { NsecSigner, unwrap, UnwrapError, Kind, eventId, buildRumor, seal, giftWrap, wrapMessage }
