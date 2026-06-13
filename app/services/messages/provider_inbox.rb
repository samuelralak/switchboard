# frozen_string_literal: true

module Messages
	# The provider's order ledger: every escrow order they are the provider on, surfaced as a Conversation
	# (the client, the joined service, the escrow state, and the one decision the state calls for), built from
	# the Order rows + the on-relay listing/request each order targets. The consumer mirror is Orders::Ledger.
	# The request CONTENT (the filled input schema) lives in the encrypted NIP-17 thread and is layered in
	# client-side, so `inputs` is empty here.
	class ProviderInbox < BaseService
		include ActionView::Helpers::DateHelper

		option :pubkey, type: Types::Strict::String

		# Order state -> the Conversation/Thread status symbol (provider perspective).
		STATE = {
			Orders::States::AWAITING_FUNDING => :received,
			Orders::States::FUNDED => :awaiting_fulfillment,
			Orders::States::RELEASED => :completed,
			Orders::States::REFUNDED => :refunded,
			Orders::States::EXPIRED => :expired
		}.freeze

		NOTE = {
			received: "Waiting for the client to fund the escrow before the work begins.",
			awaiting_fulfillment: "Funded. Deliver the work, then the client releases the escrow to you.",
			delivered: "Delivered. Waiting for the client to review and release the escrow.",
			completed: "Completed. The escrow released to you.",
			refunded: "Refunded to the client.",
			expired: "Expired before it was funded."
		}.freeze

		def call
			orders = Order.as_provider(pubkey).includes(:delivery).order(created_at: :desc).to_a
			@services = Orders::ServiceFor.map_for(orders)
			@clients = client_records(orders.map(&:consumer_pubkey).uniq)

			orders.map { |order| build(order) }
		end

		private

		def build(order)
			Conversation.new(**core(order), **client(order.consumer_pubkey), **service_fields(@services[order.id]))
		end

		# Order-derived fields (the escrow state + the one decision it calls for).
		def core(order)
			state = conversation_state(order)
			{
				id: order.id, sats: order.amount_sats, state:, created: "#{time_ago_in_words(order.created_at)} ago",
				deadline: nil, unread: state == :received, note: NOTE[state], inputs: [], result: nil
			}
		end

		# Funded + a delivery assertion reads as :delivered (awaiting the client's release); otherwise the plain
		# per-state mapping. result stays nil: the delivered work is end-to-end and never server-known.
		def conversation_state(order)
			return :delivered if order.current_state == Orders::States::FUNDED && order.delivery.present?

			STATE.fetch(order.current_state, :received)
		end

		# Counterparty (client) fields. peer_pubkey is the 64-hex trust anchor the browser checks the decrypted
		# order envelope's author against before rendering it.
		# Counterparty (client) fields, read from the batched @clients map (no per-conversation User query).
		def client(peer)
			record = @clients[peer]
			{ npub: npub(peer), name: record[:user]&.name.presence || npub(peer), peer_pubkey: peer, track: track(record) }
		end

		# Joined-service fields (nil-safe when the listing/request is not ingested locally).
		def service_fields(service)
			{
				service: service&.title || "Escrow order", cap: service&.capability,
				description: service.try(:description).to_s, mode: service.try(:fulfillment) || "manual", span: span(service)
			}
		end

		def span(service)
			window = service.try(:delivery_window).presence
			window && "#{window} window"
		end

		def npub(peer)
			Nostr::Bech32.npub_encode(peer)
		rescue StandardError
			peer
		end

		# The client's signed history as a consumer, so the provider can judge the request (brief §10). Reads the
		# batched release aggregate; disputes stay 0 until the dispute ledger feeds them.
		def track(record)
			year = record[:user]&.first_seen_at&.year

			TrackRecord.new(completed: record[:count], settled: record[:settled].to_s,
				since: year&.to_s, disputes: 0, fresh: record[:count].zero?)
		end

		# One users-by-pubkey map + one grouped released-order aggregate for all clients, so name/track never run
		# a query per conversation (the provider inbox is O(1) DB round-trips in the client dimension now).
		def client_records(peers)
			users = User.where(pubkey: peers).index_by(&:pubkey)
			released = Order.where(consumer_pubkey: peers).in_state(Orders::States::RELEASED)
			counts = released.group(:consumer_pubkey).count
			settled = released.group(:consumer_pubkey).sum(:amount_sats)

			peers.index_with { |peer| { user: users[peer], count: counts[peer].to_i, settled: settled[peer].to_i } }
		end
	end
end
