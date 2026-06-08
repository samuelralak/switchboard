# frozen_string_literal: true

module Messages
	module Ui
		# Render state for the order-ledger inbox: the provider's conversations, which one is open, the service
		# behind the open one (for the drawer), and the DM relay set the browser decrypts the request content
		# from. One value object so the controller stays thin. Mirrors Orders::Ui::State.
		class State
			Index = Data.define(:conversations, :selected, :thread_open, :selected_service, :dm_relays)

			# selected_id is the requested conversation (params[:id]); absent, the first opens on wide screens
			# while the list stays primary on narrow ones (thread_open false).
			def self.index(pubkey:, selected_id:)
				conversations = Messages::ProviderInbox.call(pubkey:)
				selected = conversations.find { |conversation| conversation.id == selected_id } || conversations.first

				Index.new(
					conversations:,
					selected:,
					thread_open: selected_id.present?,
					selected_service: selected && service_for(provider: pubkey, order_id: selected.id),
					dm_relays: NostrClient.configuration.dm_relays
				)
			end

			# The on-relay service the open conversation's order targets (for the drawer), scoped to the provider
			# so a stray id can't read another provider's order.
			def self.service_for(provider:, order_id:)
				order = Order.as_provider(provider).find_by(id: order_id)

				order && Orders::ServiceFor.call(order:)
			end
		end
	end
end
