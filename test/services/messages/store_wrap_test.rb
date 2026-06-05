# frozen_string_literal: true

require "test_helper"

module Messages
	# Stores an opaque kind-1059 wrap for its recipient. Validates + dedups + caps; never decrypts.
	class StoreWrapTest < ActiveSupport::TestCase
		def setup
			@recipient = Nostr::Keygen.new.generate_key_pair.public_key.to_s
		end

		test "stores a valid gift wrap keyed and tagged for its recipient" do
			wrap = gift_wrap(@recipient)

			record = StoreWrap.call(event: wrap)

			assert record.persisted?
			assert_equal @recipient, record.recipient_pubkey
			assert_equal wrap["id"], record.wrap_id
			assert_equal wrap["created_at"], record.nostr_created_at.to_i
			assert_operator record.expires_at, :>, Time.current
		end

		test "is idempotent for a re-deposited wrap" do
			wrap = gift_wrap(@recipient)
			first = StoreWrap.call(event: wrap)

			assert_no_difference -> { InboxWrap.count } do
				assert_equal first.id, StoreWrap.call(event: wrap).id
			end
		end

		test "rejects an event that is not a gift wrap" do
			note = sign_event(kind: Events::Kinds::CLASSIFIED, tags: [ %w[d x] ], content: "hi")

			assert_raises(InvalidEventError) { StoreWrap.call(event: note) }
		end

		test "rejects a gift wrap with no recipient p tag" do
			wrap = sign_event(kind: Events::Kinds::GIFT_WRAP, tags: [], content: "cipher")

			assert_raises(InvalidEventError) { StoreWrap.call(event: wrap) }
		end

		test "rejects a forged signature" do
			wrap = gift_wrap(@recipient).merge("sig" => "0" * 128)

			assert_raises(InvalidEventError) { StoreWrap.call(event: wrap) }
		end

		test "stores only the canonical event fields, dropping non-standard extra keys" do
			wrap = gift_wrap(@recipient).merge("relays" => [ "wss://x" ], "junk" => "drop me")

			record = StoreWrap.call(event: wrap)

			assert_equal %w[content created_at id kind pubkey sig tags], record.wrap.keys.sort
		end

		test "clamps the retention horizon to the wrap's NIP-40 expiration when sooner" do
			soon = 2.hours.from_now.to_i
			tags = [ [ "p", @recipient ], [ "expiration", soon.to_s ] ]
			wrap = sign_event(kind: Events::Kinds::GIFT_WRAP, content: "c", tags:)

			record = StoreWrap.call(event: wrap)

			assert_in_delta soon, record.expires_at.to_i, 1
		end

		test "raises InboxFullError (not a malformed-wrap error) once the inbox is full" do
			with_quota(1) do
				existing_wrap
				assert_raises(InboxFullError) { StoreWrap.call(event: gift_wrap(@recipient)) }
			end
		end

		test "dedups a re-deposit even when the inbox is full" do
			wrap = gift_wrap(@recipient)
			stored = StoreWrap.call(event: wrap)

			with_quota(1) do
				assert_equal stored.id, StoreWrap.call(event: wrap).id
			end
		end

		private

		def gift_wrap(recipient, content: "cipher")
			sign_event(kind: Events::Kinds::GIFT_WRAP, tags: [ [ "p", recipient ] ], content:)
		end

		def existing_wrap
			attrs = { recipient_pubkey: @recipient, wrap_id: SecureRandom.hex(32), wrap: { "kind" => 1059 } }
			InboxWrap.create!(**attrs, nostr_created_at: Time.current, expires_at: 1.day.from_now)
		end

		# Temporarily shrink the per-recipient cap so the quota path is exercised without 10k rows.
		def with_quota(limit)
			original = InboxWrap::PER_RECIPIENT_QUOTA
			InboxWrap.send(:remove_const, :PER_RECIPIENT_QUOTA)
			InboxWrap.const_set(:PER_RECIPIENT_QUOTA, limit)
			yield
		ensure
			InboxWrap.send(:remove_const, :PER_RECIPIENT_QUOTA)
			InboxWrap.const_set(:PER_RECIPIENT_QUOTA, original)
		end
	end
end
