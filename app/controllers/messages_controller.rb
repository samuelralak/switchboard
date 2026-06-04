# frozen_string_literal: true

# The messages inbox: order-scoped threads (NIP-17 DMs), shown as the client's request
# ledger. UI-first with placeholder data from Messages::Inbox until the gift-wrap decrypt
# layer lands. :id (the show path) opens a thread; without it the first one opens on wide
# screens while the list stays primary on narrow ones.
class MessagesController < ApplicationController
	def index
		@conversations = Messages::Inbox.conversations
		@thread_open = params[:id].present?
		@selected = selected_conversation
	end

	private

	def selected_conversation
		@conversations.find { |conversation| conversation.id == params[:id] } || @conversations.first
	end
end
