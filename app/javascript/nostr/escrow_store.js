// Shared per-origin IndexedDB for browser-held escrow material (brief sec 6.3: never sent to the runtime).
// One database, one version; add a store name here and bump VERSION when the schema grows.
const DB_NAME = "switchboard"
const VERSION = 2
const STORES = [ "escrow_keys", "escrow_secrets", "escrow_payouts" ]

function openDb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, VERSION)
    req.onupgradeneeded = () => {
      const db = req.result
      for (const name of STORES) if (!db.objectStoreNames.contains(name)) db.createObjectStore(name)
    }
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error)
  })
}

function request(req) {
  return new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error)
  })
}

export async function idbGet(store, key) {
  const db = await openDb()
  try {
    return (await request(db.transaction(store, "readonly").objectStore(store).get(key))) ?? null
  } finally {
    db.close()
  }
}

export async function idbPut(store, key, value) {
  const db = await openDb()
  try {
    await request(db.transaction(store, "readwrite").objectStore(store).put(value, key))
  } finally {
    db.close()
  }
}
