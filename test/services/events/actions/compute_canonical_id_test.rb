# frozen_string_literal: true

require "test_helper"

module Events
	module Actions
		class ComputeCanonicalIdTest < ActiveSupport::TestCase
			# NIP-59 published example (nips/59.md, vendored): the rumor id must match what
			# nostr-tools computed, proving cross-implementation canonical-serialization parity.
			test "matches the NIP-59 published rumor id" do
				rumor = JSON.parse(Rails.root.join("test/fixtures/files/nip59.vector.json").read).fetch("expected_rumor")
				assert_equal rumor["id"], Events::Actions::ComputeCanonicalId.call(event: rumor)
			end

			test "treats symbol and string keys identically" do
				attrs = { pubkey: "a" * 64, created_at: 1, kind: 1, tags: [], content: "hi" }
				from_strings = Events::Actions::ComputeCanonicalId.call(event: attrs.transform_keys(&:to_s))
				from_symbols = Events::Actions::ComputeCanonicalId.call(event: attrs)
				assert_equal from_strings, from_symbols
			end

			test "keeps & < > literal in the canonical serialization (never HTML-escaped)" do
				event = { "pubkey" => "a" * 64, "created_at" => 1, "kind" => 1, "tags" => [], "content" => "A & B < C >" }
				canonical = JSON.generate([ 0, "a" * 64, 1, 1, [], "A & B < C >" ])
				assert_includes canonical, "A & B < C >"
				assert_equal Digest::SHA256.hexdigest(canonical), Events::Actions::ComputeCanonicalId.call(event: event)
			end

			# Thin serializer: it hashes whatever fields are present and validates nothing
			# (presence/typing is the caller's job, e.g. Unwrap#assert_typed!).
			test "hashes an empty event without raising" do
				assert_nothing_raised { Events::Actions::ComputeCanonicalId.call(event: {}) }
				expected = Digest::SHA256.hexdigest(JSON.generate([ 0, nil, nil, nil, nil, nil ]))
				assert_equal expected, Events::Actions::ComputeCanonicalId.call(event: {})
			end

			# R2 regression: a field that JSON.parse accepts but JSON.generate cannot serialize (an
			# invalid-encoding string) must surface as a discardable InvalidEventError, never a raw
			# JSON::GeneratorError that bypasses discard_on and retry-storms the ingest job.
			test "raises InvalidEventError when a field cannot be canonicalized (invalid encoding)" do
				bad = (+"\xFF").force_encoding("UTF-8")
				event = { "pubkey" => "a" * 64, "created_at" => 1, "kind" => 1, "tags" => [], "content" => bad }
				assert_raises(InvalidEventError) { Events::Actions::ComputeCanonicalId.call(event:) }
			end
		end
	end
end
