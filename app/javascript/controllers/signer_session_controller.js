import { Controller } from "@hotwired/stimulus"

// Clears the in-memory signer and forgets the session reconnect descriptors when the user disconnects
// (signs out). The saved NIP-49 ciphertext is kept (the user's remember-this-device convenience,
// removed only via "forget key"). Wired to the disconnect form's submit.
export default class extends Controller {
  async forget() {
    const { clearSigner } = await import("nostr/signer_store")
    clearSigner()
  }
}
