# frozen_string_literal: true

require "test_helper"

# The operator's persisted default-view setting: a single row, validated, that Attestation::Policy reads ahead
# of the ENV/default fallback.
class AttestationSettingTest < ActiveSupport::TestCase
	test "policy is nil when unset, so the caller falls back to ENV/default" do
		assert_nil AttestationSetting.policy
	end

	test "assign_policy creates the single row and reads back" do
		AttestationSetting.assign_policy("badge")

		assert_equal "badge", AttestationSetting.policy
		assert_equal 1, AttestationSetting.count
	end

	test "assign_policy updates the existing row instead of adding another" do
		AttestationSetting.assign_policy("badge")
		AttestationSetting.assign_policy("off")

		assert_equal "off", AttestationSetting.policy
		assert_equal 1, AttestationSetting.count
	end

	test "rejects a policy outside Attestation::POLICIES" do
		assert_raises(ActiveRecord::RecordInvalid) { AttestationSetting.assign_policy("bogus") }
	end

	test "the singleton index forbids a second row" do
		AttestationSetting.create!(policy: "badge")

		assert_raises(ActiveRecord::RecordNotUnique) { AttestationSetting.create!(policy: "off") }
	end
end
