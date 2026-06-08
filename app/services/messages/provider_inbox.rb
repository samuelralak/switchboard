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
			Order.as_provider(pubkey).order(created_at: :desc).map { |order| build(order) }
		end

		private

		def build(order)
			Conversation.new(**core(order), **client(order.consumer_pubkey), **service_fields(Orders::ServiceFor.call(order:)))
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
		def client(peer) = { npub: npub(peer), name: name(peer), peer_pubkey: peer, track: track(peer) }

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

		def name(peer) = User.find_by(pubkey: peer)&.name.presence || npub(peer)

		def npub(peer)
			Nostr::Bech32.npub_encode(peer)
		rescue StandardError
			peer
		end

		# The client's signed history as a consumer, so the provider can judge the request (brief §10).
		def track(peer)
			released = Order.as_consumer(peer).in_state(Orders::States::RELEASED)
			since = User.find_by(pubkey: peer)&.first_seen_at&.year

			TrackRecord.new(completed: released.count, settled: released.sum(:amount_sats).to_s,
				since: since&.to_s, disputes: 0, fresh: released.empty?)
		end
	end
end
