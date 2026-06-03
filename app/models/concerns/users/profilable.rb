# frozen_string_literal: true

module Users
	# Derives the denormalized profile columns from a verified kind-0 (metadata) event:
	# parses the content JSON (canonicalizing deprecated aliases), reads NIP-39 `i` tags,
	# and records provenance. Mirrors Events::Ingestable's before_validation derivation.
	module Profilable
		extend ActiveSupport::Concern

		# Deprecated kind-0 content keys mapped to our column names (NIP-01/NIP-24).
		ALIASES = {
			"username" => "name",
			"displayName" => "display_name",
			"image" => "picture",
			"bio" => "about"
		}.freeze

		# String columns read straight from content (after aliasing).
		STRING_FIELDS = %w[name display_name about picture banner website nip05 lud16 lud06].freeze

		included do
			before_validation :set_first_seen_at, on: :create
		end

		# Project a verified kind-0 event onto this row. A newer kind-0 replaces every field
		# wholesale: a sparse event legitimately blanks fields, so we never merge with the old.
		def assign_kind0(event_data)
			content = parse_content(event_data["content"])

			assign_profile(content, event_data["tags"])
			assign_provenance(event_data)
			reset_nip05_verification if nip05_changed?
		end

		private

		def set_first_seen_at
			self.first_seen_at ||= Time.current
		end

		def assign_profile(content, tags)
			assign_string_fields(content)
			self.bot = content["bot"] == true
			self.external_identities = identities_from(tags)
		end

		def assign_provenance(event_data)
			self.metadata_event_id = event_data["id"]
			self.nostr_created_at = Time.at(event_data["created_at"].to_i).utc
		end

		# kind-0 content is stringified JSON; a malformed or non-object body yields no fields.
		def parse_content(raw)
			parsed = JSON.parse(raw.to_s)
			parsed.is_a?(Hash) ? parsed : {}
		rescue JSON::ParserError
			{}
		end

		def assign_string_fields(content)
			STRING_FIELDS.each do |field|
				value = content[field]
				value = content[ALIASES.key(field)] if value.nil?
				self[field] = value.is_a?(String) ? value.strip.presence : nil
			end
		end

		# NIP-39: ["i", "<platform>:<identity>", "<proof>"] -> {platform, identity, proof}.
		def identities_from(tags)
			Array(tags).filter_map do |tag|
				next unless tag.is_a?(Array) && tag[0] == "i" && tag[1].is_a?(String)

				platform, identity = tag[1].split(":", 2)
				next if platform.blank? || identity.blank?

				{ "platform" => platform, "identity" => identity, "proof" => tag[2] }
			end
		end

		def reset_nip05_verification
			self.nip05_verified = false
			self.nip05_verified_at = nil
		end
	end
end
