# frozen_string_literal: true

# A user's public profile = their two-sided marketplace presence (identity + the services they offer and the
# requests they have posted), viewer-aware so the owner additionally gets manage controls. Public + npub-keyed,
# so it is shareable. Profiles::Resolve owns the resolution use-case (404 on a malformed npub, a lazy kind-0
# fetch + placeholder on a not-yet-projected one) and returns the render state; the action just hands it off.
class ProfilesController < ApplicationController
	def show
		@portfolio = Profiles::Resolve.call(npub: params[:npub], viewer: current_user)
	end
end
