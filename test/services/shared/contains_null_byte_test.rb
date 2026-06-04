# frozen_string_literal: true

require "test_helper"

module Shared
	class ContainsNullByteTest < ActiveSupport::TestCase
		test "detects a NUL byte nested in strings, arrays, and hashes" do
			assert Shared::ContainsNullByte.call(value: "a#{0.chr}b")
			assert Shared::ContainsNullByte.call(value: [ "ok", [ "x#{0.chr}" ] ])
			assert Shared::ContainsNullByte.call(value: { "k" => { "n" => "v#{0.chr}" } })
			assert Shared::ContainsNullByte.call(value: { "k#{0.chr}" => "v" })
			assert Shared::ContainsNullByte.call(value: { sym: [ { "deep#{0.chr}" => 1 } ] })
		end

		test "passes clean structures and non-string scalars through" do
			assert_not Shared::ContainsNullByte.call(value: "hello")
			assert_not Shared::ContainsNullByte.call(value: [ "a", { "b" => 1 } ])
			assert_not Shared::ContainsNullByte.call(value: 12_345)
			assert_not Shared::ContainsNullByte.call(value: nil)
		end
	end
end
