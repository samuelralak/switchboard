# frozen_string_literal: true

require "test_helper"

module Events
	class VerifyHttpAuthTest < ActiveSupport::TestCase
		URL = "https://switchboard.test/api/x"

		test "returns the verified event for a well-formed NIP-98 request" do
			event = sign_nip98(tags: nip98_tags(url: URL))

			assert_equal event["pubkey"], verify(event)["pubkey"]
		end

		test "rejects the wrong kind" do
			event = sign_nip98(tags: nip98_tags(url: URL), kind: 1)

			assert_raises(AuthenticationError) { verify(event) }
		end

		test "rejects a stale timestamp" do
			event = sign_nip98(tags: nip98_tags(url: URL), created_at: 1.hour.ago.to_i)

			assert_raises(AuthenticationError) { verify(event) }
		end

		test "honors the past timestamp window boundary" do
			window = VerifyHttpAuth::TIMESTAMP_WINDOW
			freeze_time do
				edge = sign_nip98(tags: nip98_tags(url: URL), created_at: window.seconds.ago.to_i)
				past = sign_nip98(tags: nip98_tags(url: URL), created_at: (window + 1).seconds.ago.to_i)

				assert_equal edge["pubkey"], verify(edge)["pubkey"]
				assert_raises(AuthenticationError) { verify(past) }
			end
		end

		test "honors the future timestamp window boundary symmetrically" do
			window = VerifyHttpAuth::TIMESTAMP_WINDOW
			freeze_time do
				edge = sign_nip98(tags: nip98_tags(url: URL), created_at: (window - 1).seconds.from_now.to_i)
				ahead = sign_nip98(tags: nip98_tags(url: URL), created_at: (window + 1).seconds.from_now.to_i)

				assert_equal edge["pubkey"], verify(edge)["pubkey"]
				assert_raises(AuthenticationError) { verify(ahead) }
			end
		end

		test "rejects a method mismatch" do
			event = sign_nip98(tags: nip98_tags(url: URL, http_method: "GET"))

			assert_raises(AuthenticationError) { verify(event, http_method: "POST") }
		end

		test "rejects a u-tag mismatch" do
			event = sign_nip98(tags: nip98_tags(url: "https://evil.test/api/x"))

			assert_raises(AuthenticationError) { verify(event) }
		end

		test "normalizes a trailing slash when matching the u tag" do
			event = sign_nip98(tags: nip98_tags(url: "#{URL}/"))

			assert_equal event["pubkey"], verify(event, url: URL)["pubkey"]
		end

		test "rejects a tampered event whose signature no longer matches" do
			event = sign_nip98(tags: nip98_tags(url: URL))
			event["content"] = "tampered"

			assert_raises(InvalidEventError) { verify(event) }
		end

		test "accepts a body bound by a matching payload tag" do
			body = JSON.generate(hello: "world")
			event = sign_nip98(tags: nip98_tags(url: URL, payload: Digest::SHA256.hexdigest(body)))

			assert_equal event["pubkey"], verify(event, body:)["pubkey"]
		end

		test "rejects a body whose payload tag does not match" do
			event = sign_nip98(tags: nip98_tags(url: URL, payload: Digest::SHA256.hexdigest("other")))

			assert_raises(AuthenticationError) { verify(event, body: "actual") }
		end

		test "rejects a body when the payload tag is absent" do
			event = sign_nip98(tags: nip98_tags(url: URL))

			assert_raises(AuthenticationError) { verify(event, body: "unsigned") }
		end

		private

		def verify(event, http_method: "POST", url: URL, body: nil)
			VerifyHttpAuth.call(event_data: event, http_method:, url:, body:)
		end
	end
end
