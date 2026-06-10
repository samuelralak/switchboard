# frozen_string_literal: true

module Settings
	# The non-custodial profile editor sub-page. The browser signs + broadcasts a new kind-0 itself (no server
	# write), so there is no create. `show` renders the editor from the assembled render state; `update` is the
	# post-broadcast reconcile -- a PATCH meaning "I re-published my kind-0, pull it back" -- which force-fetches
	# the just-published event (bypassing the login cooldown) so the projection catches up without a re-login.
	class ProfileController < ApplicationController
		before_action :require_login

		def show
			@profile = Ui::State.profile(user: current_user)
		end

		def update
			Users::MetadataFetchJob.perform_later(current_user.pubkey, force: true)
			head :accepted
		end
	end
end
