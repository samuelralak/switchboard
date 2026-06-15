# frozen_string_literal: true

module Admin
	# Platform settings for the operator. Today this is the default catalog view: how attestation is surfaced to
	# visitors (off | badge | exclude), which sets the default each viewer can then override. Persisted as a
	# singleton AttestationSetting so it survives deploys; Attestation::Policy reads it ahead of the ENV/default.
	class SettingsController < BaseController
		def show
			@policy = Attestation::Policy.policy
		end

		def update
			policy = params.expect(:attestation_policy)
			return redirect_to(admin_settings_path, alert: "Unknown policy.") unless Attestation::POLICIES.include?(policy)

			AttestationSetting.assign_policy(policy)

			redirect_to admin_settings_path, notice: "Default catalog view updated."
		end
	end
end
