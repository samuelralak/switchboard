// A Set with FIFO eviction past a cap, so long-lived dedup tracking (event/rumor ids across a
// multi-hour session) cannot grow without bound. The oldest id is evicted first. At the wrap-id layer
// (RelaySet.seen) an evicted id is harmless: the rumor-id layer (DmClient.seen) below it still dedups the
// re-delivered wrap. At the rumor-id layer there is no layer below, so the cap is sized so it is never
// reached in a session rather than backstopped. Drop-in for the subset of Set the dedup paths use:
// has(), add(), clear().
export class BoundedSet {
  constructor(limit = 50000) {
    this.limit = limit
    this.ids = new Set()
    this.order = []
  }

  has(id) {
    return this.ids.has(id)
  }

  add(id) {
    if (this.ids.has(id)) return

    this.ids.add(id)
    this.order.push(id)
    if (this.order.length > this.limit) this.ids.delete(this.order.shift())
  }

  clear() {
    this.ids.clear()
    this.order = []
  }
}
