# frozen_string_literal: true

# Account settings: relays today (profile, signer, notifications later). Session-authenticated; the
# relay list itself is rendered from the shared RelaysHelper (mock until NIP-65 ingestion lands).
class SettingsController < ApplicationController
	before_action :require_login

	def show; end
end
