# frozen_string_literal: true

module Settings
	# The non-custodial relay-list (NIP-65) editor sub-page. The browser signs + broadcasts the kind-10002
	# itself (no server write), so there is no create. `show` renders the editor from the assembled render
	# state; `update` is the post-broadcast reconcile -- a PATCH meaning "I re-published my relay list, pull it
	# back" -- which force-fetches the just-published event (bypassing the login cooldown) so the projection
	# catches up without a re-login. Mirrors Settings::ProfileController.
	class RelaysController < ApplicationController
		before_action :require_login

		def show
			@relays = Ui::State.relays(user: current_user)
		end

		def update
			Users::RelayListFetchJob.perform_later(current_user.pubkey, force: true)
			head :accepted
		end
	end
end
