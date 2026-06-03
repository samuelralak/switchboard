# frozen_string_literal: true

require "test_helper"
require "nostr"

module Events
	class VerifyTest < ActiveSupport::TestCase
		test "accepts a correctly-signed event whose content and tags contain & < >" do
			event = signed_event(
				content: "Logo, brand identity & guidelines <v2>",
				tags: [ [ "d", "logo" ], [ "title", "Design & branding" ] ]
			)

			assert_equal event, Events::Verify.call(event_data: event)
		end

		test "rejects an event whose id does not match its canonical hash" do
			event = signed_event(content: "original", tags: [ [ "d", "x" ] ])
			event["content"] = "tampered"

			error = assert_raises(InvalidEventError) { Events::Verify.call(event_data: event) }
			assert_match(/id mismatch/, error.message)
		end

		test "rejects an event with a valid id but a bad signature" do
			event = signed_event(content: "hello", tags: [ [ "d", "x" ] ])
			event["sig"] = "0" * 128

			assert_raises(InvalidEventError) { Events::Verify.call(event_data: event) }
		end

		test "rejects an event whose created_at is not an integer" do
			event = signed_event(content: "hello", tags: [ [ "d", "x" ] ])
			event["created_at"] = event["created_at"].to_s

			error = assert_raises(InvalidEventError) { Events::Verify.call(event_data: event) }
			assert_match(/integer/, error.message)
		end

		test "rejects an event whose kind is not an integer" do
			event = signed_event(content: "hello", tags: [ [ "d", "x" ] ])
			event["kind"] = event["kind"].to_s

			error = assert_raises(InvalidEventError) { Events::Verify.call(event_data: event) }
			assert_match(/integer/, error.message)
		end

		test "rejects a null byte in content" do
			event = signed_event(content: "a#{0.chr}b", tags: [ [ "d", "x" ] ])

			error = assert_raises(InvalidEventError) { Events::Verify.call(event_data: event) }
			assert_match(/null byte/, error.message)
		end

		test "rejects a null byte in an unknown extra key" do
			event = signed_event(content: "hi", tags: [ [ "d", "x" ] ])
			event["relay_note"] = "a#{0.chr}b"

			error = assert_raises(InvalidEventError) { Events::Verify.call(event_data: event) }
			assert_match(/null byte/, error.message)
		end

		test "rejects a null byte inside a tag value" do
			event = signed_event(content: "hi", tags: [ [ "d", "x" ], [ "title", "Lo#{0.chr}go" ] ])

			error = assert_raises(InvalidEventError) { Events::Verify.call(event_data: event) }
			assert_match(/null byte/, error.message)
		end

		private

		def signed_event(content:, tags:, kind: Events::Kinds::CLASSIFIED, created_at: Time.now.to_i)
			keypair = Nostr::Keygen.new.generate_key_pair
			pubkey = keypair.public_key.to_s
			id = Digest::SHA256.hexdigest(JSON.generate([ 0, pubkey, created_at, kind, tags, content ]))
			sig = Nostr::Crypto.new.sign_message(id, keypair.private_key).to_s
			{
				"id" => id, "pubkey" => pubkey, "created_at" => created_at, "kind" => kind,
				"tags" => tags, "content" => content, "sig" => sig
			}
		end
	end
end
