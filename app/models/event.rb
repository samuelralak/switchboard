# frozen_string_literal: true

# A Nostr event ingested from a relay: the verbatim wire event (`raw_event`)
# plus the columns indexed for querying.
class Event < ApplicationRecord
	include Events::Ingestable

	# The canonical NIP-01 wire fields persisted in raw_event. A hostile/buggy relay can append arbitrary
	# extra top-level keys; we keep only these so raw_event cannot bloat the jsonb (the id is hashed from the
	# canonical serialization, so dropping extras never changes it, and re-feeding raw_event re-verifies).
	WIRE_KEYS = %w[id pubkey created_at kind tags content sig].freeze

	# The author's projected identity (joined by pubkey); nil until a kind-0 is seen.
	belongs_to :author, class_name: "User", primary_key: :pubkey, foreign_key: :pubkey, optional: true

	validates :event_id, presence: true, uniqueness: true, format: { with: Events::Kinds::HEX64 }
	validates :pubkey, presence: true, format: { with: Events::Kinds::HEX64 }
	validates :sig, presence: true, format: { with: Events::Kinds::HEX128 }
	validates :kind, presence: true,
																	numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 65_535 }
	validates :nostr_created_at, :first_seen_at, :raw_event, presence: true
	validate :tags_is_array

	scope :recent, -> { order(nostr_created_at: :desc, event_id: :asc) } # NIP-01 tie-break: lower id wins
	scope :of_kind, ->(kind) { where(kind:) }
	scope :classified, -> { of_kind(Events::Kinds::CLASSIFIED) } # NIP-99 service listings
	scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) } # NIP-40 (not expired)
	scope :with_tag, ->(name, value) { where("tags @> ?", [ [ name, value ] ].to_json) } # GIN-indexed tag facet
	scope :without_tag, ->(name, value) { where.not("tags @> ?", [ [ name, value ] ].to_json) } # the inverse facet
	scope :not_unpublished, -> { without_tag("status", "inactive") } # drops author-hidden (status) events
	scope :by_author, ->(pubkey) { where(pubkey:) }
	# Operator takedown: hide content from flagged authors. `flagged` is operator state on the user
	# projection, preserved across re-projection (Users::Upsert#assign_kind0 never touches it). Empty
	# subquery (no flagged users) leaves every row, so this is a no-op cost in the common case.
	scope :not_from_flagged, -> { where.not(pubkey: User.where(flagged: true).select(:pubkey)) }

	# A kind:pubkey:d coordinate -> the single matching event, or nil.
	def self.by_coordinate(coordinate)
		kind, pubkey, d_tag = coordinate.to_s.split(":", 3)
		find_by(kind: kind.to_i, pubkey:, d_tag: d_tag.to_s)
	end

	# This event's addressable coordinate (the inverse of by_coordinate).
	def coordinate = "#{kind}:#{pubkey}:#{d_tag}"

	# First value of the first tag named `name`, or nil. e.g. tag("title").
	def tag(name)
		tags.find { |t| t.is_a?(Array) && t[0] == name }&.dig(1)
	end

	# Every value (2nd element) of every tag named `name`. e.g. tag_values("t").
	def tag_values(name)
		tags.select { |t| t.is_a?(Array) && t[0] == name }.filter_map { |t| t[1] }
	end

	def classification = Events::Kinds.classification(kind)

	private

	def tags_is_array
		errors.add(:tags, "must be an array") unless tags.is_a?(Array)
	end
end
