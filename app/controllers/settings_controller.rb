# frozen_string_literal: true

# Account settings landing: redirects to the default section. The sections themselves are sub-pages under
# the Settings:: namespace (profile, relays, ...), each rendering the shared settings rail.
class SettingsController < ApplicationController
	before_action :require_login

	def show = redirect_to settings_profile_path
end
