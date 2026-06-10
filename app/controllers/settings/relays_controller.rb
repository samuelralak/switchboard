# frozen_string_literal: true

module Settings
	# The relays settings sub-page: lists the user's NIP-65 relays (RelaysHelper#display_relays) with a Manage
	# affordance into the shared relays dialog. Read-only here.
	class RelaysController < ApplicationController
		before_action :require_login

		def show; end
	end
end
