# frozen_string_literal: true

require "test_helper"

module Attestation
	# Policy resolution precedence (persisted -> ENV/config -> default) and the operator default view.
	class PolicyTest < ActiveSupport::TestCase
		test "falls back to the ENV/config value when nothing is persisted" do
			with_policy("badge") do
				assert_equal "badge", Policy.policy
			end
		end

		test "the persisted operator value wins over the ENV/config value" do
			AttestationSetting.assign_policy("off")

			with_policy("badge") do
				assert_equal "off", Policy.policy
			end
		end

		test "falls back to the default when neither persisted nor configured" do
			with_policy("") do
				assert_equal Attestation::DEFAULT_POLICY, Policy.policy
			end
		end

		test "default_view maps exclude to verified and everything else to all" do
			with_policy("exclude") { assert_equal "verified", Policy.default_view }
			with_policy("badge") { assert_equal "all", Policy.default_view }
		end

		test "enabled? is true under badge/exclude with an issuer and false under off" do
			# The suite has an issuer key (R_op) configured, so issuer_pubkey is present.
			with_policy("badge") { assert Policy.enabled? }
			with_policy("exclude") { assert Policy.enabled? }
			with_policy("off") { assert_not Policy.enabled? }
		end
	end
end
