# frozen_string_literal: true

require "test_helper"

module Events
	class ContractTest < ActiveSupport::TestCase
		test "accepts a well-formed event" do
			assert Events::Contract.new.call(valid).success?
		end

		test "rejects too many tags" do
			result = Events::Contract.new.call(valid.merge(tags: Array.new(2_001) { [ "t", "x" ] }))
			assert_includes messages(result), "too many tags"
		end

		test "rejects oversized tags within the count limit" do
			result = Events::Contract.new.call(valid.merge(tags: [ [ "x", "a" * 70_000 ] ]))
			assert_includes messages(result), "tags too large"
		end

		test "rejects an already-expired event" do
			result = Events::Contract.new.call(valid.merge(tags: [ [ "expiration", 1.hour.ago.to_i.to_s ] ]))
			assert_includes messages(result), "event has expired"
		end

		test "rejects a negative created_at" do
			result = Events::Contract.new.call(valid.merge(created_at: -1))
			assert_includes messages(result), "must be a positive unix timestamp"
		end

		test "rejects a created_at too far in the future" do
			result = Events::Contract.new.call(valid.merge(created_at: Time.now.to_i + 3600))
			assert_includes messages(result), "too far in the future"
		end

		test "rejects a d tag longer than the column limit" do
			result = Events::Contract.new.call(valid.merge(tags: [ [ "d", "x" * 256 ] ]))
			assert_includes messages(result), "d tag too long"
		end

		test "rejects an oversized d tag hidden behind a value-less d tag" do
			result = Events::Contract.new.call(valid.merge(tags: [ [ "d" ], [ "d", "x" * 256 ] ]))
			assert_includes messages(result), "d tag too long"
		end

		private

		def valid
			{
				id: "a" * 64, pubkey: "b" * 64, sig: "c" * 128, kind: 30_402,
				created_at: Time.now.to_i, tags: [ [ "d", "x" ] ], content: "hello"
			}
		end

		def messages(result) = result.errors.map(&:text)
	end
end
