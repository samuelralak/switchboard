# frozen_string_literal: true

# The generic NIP-17 DM proof (#32): a keyless-browser client surface, NOT the order-scoped messaging
# UI (that is messages#index). Session-authenticated; the view hands the browser the signed-in pubkey,
# the DM relay list, and the inbox URL via data-* attributes so the client can subscribe, publish, and
# use the cold-start cache. No message ever passes through the server (it holds no user key).
class DirectMessagesController < ApplicationController
	before_action :require_login

	def index
		@pubkey = Current.user.pubkey
		@dm_relays = NostrClient.configuration.dm_relays
	end
end
