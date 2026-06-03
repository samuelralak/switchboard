# frozen_string_literal: true

# A Nostr event ingested from a relay: the verbatim wire event (`raw_event`)
# plus the columns indexed for querying.
class Event < ApplicationRecord
	include Events::Ingestable

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
	scope :classified, -> { of_kind(Events::Kinds::CLASSIFIED) }                       # NIP-99 service listings
	scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }  # NIP-40 (not expired)
	scope :with_tag, ->(name, value) { where("tags @> ?", [ [ name, value ] ].to_json) } # GIN-indexed tag facet

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
