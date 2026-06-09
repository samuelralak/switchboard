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

	# Bech32 npub for display; falls back to raw hex if encoding fails.
	def npub
		Nostr::Bech32.npub_encode(pubkey)
	rescue StandardError
		pubkey
	end

	# NIP-24 display fallback chain: display_name -> name -> npub.
	def display = display_name.presence || name.presence || npub

	# This identity's catalog events, joined by pubkey (Event belongs_to :author).
	def events = Event.by_author(pubkey)
	def listings = events.classified.active

	private

	def external_identities_is_array
		errors.add(:external_identities, "must be an array") unless external_identities.is_a?(Array)
	end
end
