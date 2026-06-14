# How escrow works in Switchboard

**Principle: the platform never holds your money.** Funds are locked at a Cashu mint by cryptographic rules. Only the consumer and provider (and, for disputes, a co-signing arbiter) can move them. The Rails server records only what it can observe, never a key or a spendable token.

## The pieces

```mermaid
flowchart LR
    C["Consumer browser"]
    P["Provider browser"]
    M[("Cashu mint")]
    R["Rails server"]
    N{{"Nostr relays"}}

    C -->|mint + lock| M
    P -->|verify + redeem| M
    C -->|encrypted token DM| N
    N --> P
    C -->|observable report| R
    R -->|reads outcome| M
```

- **Browser (both parties):** holds all keys, mints the ecash, signs the locks and unlocks. The money path lives entirely here.
- **Cashu mint (vetted, currently Coinos):** issues the ecash and enforces the lock (hashlock, timelock, required signatures). It holds the backing sats while an order is locked.
- **Rails server:** records observable order state and runs a reconcile sweep that reads the mint to learn the outcome. It never sees keys, preimages, proof secrets, or tokens.
- **Nostr relays:** carry the signed listings/requests, and the encrypted (NIP-17) hand-off of the locked token between the two parties.

## Lifecycle (Tier 1, the default)

```mermaid
sequenceDiagram
    autonumber
    participant C as Consumer
    participant M as Mint
    participant P as Provider
    participant R as Rails

    C->>M: Mint ecash over Lightning (amount + mint fee)
    C->>M: Lock exactly `amount` to provider as an HTLC (timelock refund)
    C-->>P: Send locked token over encrypted Nostr DM
    P->>M: Verify lock (unspent, locked to me, amount, hashlock)
    Note over P: Provider does the work

    alt Delivered and accepted
        C-->>P: Reveal preimage
        P->>M: Redeem with preimage (a mint swap)
        M-->>P: Pays provider `amount` minus the redeem fee
    else Never delivered
        C->>M: Refund after the timelock
        M-->>C: Returns the budget to the consumer
    end

    R->>M: Reconcile sweep reads mint state
    Note over R: Records RELEASED or REFUNDED
```

The **mint** decides the outcome; Rails only observes it.

## Order states

```mermaid
stateDiagram-v2
    [*] --> awaiting_funding
    awaiting_funding --> funded: consumer funds (locks at the mint)
    funded --> released: provider redeems (Tier 1: with preimage)
    funded --> refunded: consumer refunds after the timelock
    funded --> disputed: Tier 2 only, either party escalates
    disputed --> released: arbiter rules for the provider
    disputed --> refunded: arbiter rules for the consumer
    released --> [*]
    refunded --> [*]
```

## Two tiers

- **Tier 1 (NUT-14 HTLC), default.** Consumer-gated and fully self-custodial: the provider can only redeem with the consumer's preimage, and the consumer can refund after the timelock. No third party. Cap ~100k sat.
- **Tier 2 (NUT-11 P2PK 2-of-3 arbiter), opt-in for subjective work.** The lock needs 2 of 3 signers: consumer, provider, platform arbiter. Lower cap (~25k sat) and a longer minimum locktime so a dispute has time to resolve.

```mermaid
sequenceDiagram
    autonumber
    participant C as Consumer
    participant P as Provider
    participant A as Arbiter
    participant M as Mint

    Note over C,M: Funded as a 2-of-3 P2PK lock (consumer + provider + arbiter)

    alt Happy path (no dispute)
        C-->>P: Co-sign the locked proofs
        P->>M: Add provider co-signature, redeem (2 of 3)
        M-->>P: Pays provider `amount` minus the redeem fee
    else Dispute
        C->>A: Either party escalates
        Note over A: Reviews and rules for provider or consumer
        A-->>P: Co-signs to the ruled winner
        P->>M: Winner adds own co-signature, redeems (2 of 3)
    end

    Note over A: Arbiter is 1-of-3: signs only the secret, never holds proofs, never moves funds alone
```

## What the server stores vs never sees

- **Stored (observable, non-spendable):** order amount, mint URL, proof Y-values (hashes), hashlock, locktime, public keys, state.
- **Never:** private keys, preimages, proof secrets, or the spendable token. All of that stays in the browser.

## Fees and amounts

The lock is the full order amount, but redeeming it is itself a mint swap, so the provider does **not** receive the full amount.

- **Consumer pays:** the order amount plus the mint's swap fee for the lock (itemized before they pay).
- **Locked to the provider:** exactly the order amount.
- **Provider receives:** the order amount **minus the mint's redeem swap fee**. If they then cash the ecash out to Lightning, the mint takes a further small melt fee.
- **No platform cut at any step.** Every fee belongs to the mint, not to Switchboard.

## The one trust assumption

The mint custodies the backing sats while an order is locked, so a dead or dishonest mint is the real risk, not the platform. This is mitigated by a vetted mint allowlist (currently Coinos) and disclosed to users at funding. Keep amounts modest while the platform is young.
