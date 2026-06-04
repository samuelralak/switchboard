# frozen_string_literal: true

require "test_helper"

module Events
	class KindsTest < ActiveSupport::TestCase
		test "classifies the NIP-65 and NIP-17 relay-list kinds as replaceable and storable" do
			assert_equal :replaceable, Kinds.classification(Kinds::RELAY_LIST)
			assert_equal :replaceable, Kinds.classification(Kinds::RELAY_LIST_DM)
			assert Kinds.storable?(Kinds::RELAY_LIST_DM)
			assert_not Kinds.ephemeral?(Kinds::RELAY_LIST_DM)
		end

		test "classifies the gift wrap and seal as regular and storable" do
			assert_equal :regular, Kinds.classification(Kinds::GIFT_WRAP)
			assert_equal :regular, Kinds.classification(Kinds::SEAL)
			assert Kinds.storable?(Kinds::GIFT_WRAP)
		end
	end
end
