// Blossom (NIP-B7) blob upload for the provider studio. Non-custodial: each upload is authorized by a
// kind-24242 event the USER's signer signs (the key never leaves the signer); the server stores the
// blob content-addressed by sha256 and returns a Blob Descriptor (BUD-02). Verified live against
// blossom.band (BUD-01/02/06/11): CORS allows a browser PUT, real images return 201 + a retrievable
// https URL of the form https://<npub>.blossom.band/<sha256>.<ext>.
//
// blossom.band is run by nostr.build. Free tier: <=20 MiB; png/jpeg/webp/gif; images carrying GPS EXIF
// are rejected. The default can be overridden per the user's kind:10063 server list later.
export const DEFAULT_BLOSSOM_SERVER = "https://blossom.band"

// MIME types we offer for a listing image (blossom.band free tier, minus non-raster formats).
export const ALLOWED_IMAGE_TYPES = ["image/png", "image/jpeg", "image/webp", "image/gif"]
export const MAX_IMAGE_BYTES = 20 * 1024 * 1024 // 20 MiB free-tier ceiling

// Lowercase hex sha256 of an ArrayBuffer, via the platform SubtleCrypto (no dependency).
export async function sha256Hex(buffer) {
  const digest = await crypto.subtle.digest("SHA-256", buffer)
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("")
}

// Natural pixel size of an image File as the NIP-92 "WIDTHxHEIGHT" string, or null if undecodable.
export async function imageDimensions(file) {
  try {
    const bitmap = await createImageBitmap(file)
    const dim = `${bitmap.width}x${bitmap.height}`
    bitmap.close?.()
    return dim
  } catch {
    return null
  }
}

// Upload a File to a Blossom server, authorized by `signer` (anything with signEvent(template)). Returns
// the NIP-92 imeta fields for the stored blob: { url, m, x, dim, size }. Throws Error(message) on
// rejection, preferring the server's human-readable X-Reason.
export async function uploadImage(file, signer, { server = DEFAULT_BLOSSOM_SERVER } = {}) {
  const buffer = await file.arrayBuffer()
  const x = await sha256Hex(buffer)
  const now = Math.floor(Date.now() / 1000)

  const auth = await signer.signEvent({
    kind: 24242,
    created_at: now,
    content: "Upload a Switchboard listing image",
    tags: [["t", "upload"], ["expiration", String(now + 600)], ["x", x]],
  })

  const response = await fetch(`${server}/upload`, {
    method: "PUT",
    headers: { Authorization: `Nostr ${btoa(JSON.stringify(auth))}`, "Content-Type": file.type },
    body: file,
  })
  if (!response.ok) throw new Error(uploadError(response))

  const descriptor = await response.json()
  const dim = await imageDimensions(file)
  return { url: descriptor.url, m: descriptor.type || file.type, x: descriptor.sha256 || x, dim, size: descriptor.size }
}

function uploadError(response) {
  const reason = response.headers.get("x-reason")
  if (reason) return reason
  const messages = {
    400: "The server rejected the image (it may contain location/EXIF data).",
    401: "Upload not authorized. Sign the request with your key and try again.",
    402: "This server requires payment for uploads.",
    413: "Image is too large (max 20 MiB).",
    415: "Unsupported image type.",
    429: "Too many uploads, slow down for a moment.",
    500: "The server couldn't process this image. Try a different file.",
  }
  return messages[response.status] || `Upload failed (HTTP ${response.status}).`
}
