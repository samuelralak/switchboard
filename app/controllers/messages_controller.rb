# frozen_string_literal: true

# The provider's order ledger: every escrow order the signed-in user is the provider on, as a conversation
# joined to its service + state. Messages::Ui::State composes the page (the conversations, which one is open,
# its service for the drawer, and the DM relays). :id (the show path) opens a thread; without it the first
# opens on wide screens while the list stays primary on narrow ones.
class MessagesController < ApplicationController
	before_action :require_login

	# The inbox is folded into the order hub's Selling tab; without a thread id this just redirects there. With
	# an id it still renders the order's thread (reached from a Selling row) until messaging moves inline.
	def index
		return redirect_to orders_path(tab: "selling") unless params[:id]

		@state = Messages::Ui::State.index(pubkey: current_user.pubkey, selected_id: params[:id])
		@open_order = @state.conversations.find { |conversation| conversation.id == params[:order_id] }
	end
end
