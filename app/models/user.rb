# frozen_string_literal: true

# A Nostr user identity: a pubkey plus the profile projected from its latest kind-0
# (metadata) event. The winning kind-0 Event is the source of truth; this row is its
# queryable projection, kept newest-per-pubkey by Users::Upsert.
class User < ApplicationRecord
	include Users::Profilable

	has_many :sessions, dependent: :destroy # revocable login sessions (Rails 8 auth)
	# NIP-65 relays projected from this pubkey's latest kind:10002 (write relays feed the catalog ingest).
	has_many :user_relays, primary_key: :pubkey, foreign_key: :pubkey, dependent: :destroy, inverse_of: :user

	# Uniqueness is enforced by the DB unique index, not a (racy) model validation.
	validates :pubkey, presence: true, format: { with: Events::Kinds::HEX64 }
	validates :first_seen_at, presence: true
	validate :external_identities_is_array

	# Decode an npub to its hex pubkey, or nil when it is not a valid npub (rejects nsec/naddr/malformed). The
	# hex comes back even for a pubkey we have no row for, so a profile can lazily fetch an unindexed identity.
	def self.pubkey_from_npub(npub)
		hrp, hex = Nostr::Bech32.decode(npub.to_s)

		hex if hrp == "npub"
	rescue StandardError
		nil
	end

	# Operator takedown: is this pubkey flagged? Drives Event.not_from_flagged, the live-broadcast gate, the
	# profile 404, and the order-placement guard, so a flagged author's content stays hidden on every surface.
	def self.flagged?(pubkey)
		exists?(pubkey:, flagged: true)
	end

	# Bech32 npub for display; falls back to raw hex if encoding fails.
	def npub
		Nostr::Bech32.npub_encode(pubkey)
	rescue StandardError
		pubkey
	end

	# NIP-24 display fallback chain: display_name -> name -> npub.
	def display = display_name.presence || name.presence || npub

	# Whether a kind-0 name has landed yet (vs only an npub). The profile header gives a named account a sans
	# display name and a nameless one its npub rendered as data, rather than a 63-char npub as a sans heading.
	def named? = display_name.present? || name.present?

	# This identity's catalog events, joined by pubkey (Event belongs_to :author).
	def events = Event.by_author(pubkey)
	def listings = events.classified.active

	private

	def external_identities_is_array
		errors.add(:external_identities, "must be an array") unless external_identities.is_a?(Array)
	end
end
