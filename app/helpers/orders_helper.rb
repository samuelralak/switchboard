# frozen_string_literal: true

module OrdersHelper
	# Order state -> status-strip presentation; the tone mirrors the messages thread.
	ORDER_STATUS = {
		Orders::States::AWAITING_FUNDING => { tone: :copper, label: "Awaiting funding" },
		Orders::States::FUNDED => { tone: :live, label: "Funded, in escrow" },
		Orders::States::RELEASED => { tone: :settled, label: "Released to provider" },
		Orders::States::REFUNDED => { tone: :muted, label: "Refunded" },
		Orders::States::EXPIRED => { tone: :fault, label: "Expired, unfunded" }
	}.freeze

	# A funded order the provider has delivered, awaiting the consumer's release. Composed (not a state):
	# current_state stays funded; the delivery is an observable assertion off the money path.
	DELIVERED_STATUS = { tone: :copper, label: "Delivered, awaiting release" }.freeze

	TONE = {
		copper: { band: "border-copper-dim/40 bg-copper/5", lamp: "bg-copper", text: "text-copper" },
		live: { band: "border-lamp-live/30 bg-lamp-live/5", lamp: "bg-lamp-live", text: "text-lamp-live" },
		settled: { band: "border-lamp-settled/40 bg-lamp-settled/5", lamp: "bg-lamp-settled", text: "text-lamp-settled" },
		fault: { band: "border-lamp-fault/40 bg-lamp-fault/5", lamp: "bg-lamp-fault", text: "text-lamp-fault" },
		muted: { band: "border-border bg-surface", lamp: "bg-ink-faint", text: "text-ink-muted" }
	}.freeze

	def order_status(order)
		status_presentation(order.current_state, delivered: order.delivery.present?)
	end

	# The full chip presentation (tone + label + CSS) for a state, shared by the order page strip and the
	# consumer ledger rows. A funded order with a delivery assertion reads as "Delivered, awaiting release".
	def status_presentation(current_state, delivered: false)
		status = composed_status(current_state, delivered:)
		status.merge(TONE.fetch(status[:tone]))
	end

	def composed_status(current_state, delivered:)
		return DELIVERED_STATUS if current_state == Orders::States::FUNDED && delivered

		ORDER_STATUS.fetch(current_state, { tone: :muted, label: current_state })
	end

	# The turbo-frame wrapping the order detail, shared by the full page and the drawer's lazy frame.
	def order_detail_frame(order_id) = "order_#{order_id}_detail"

	# A pubkey as an npub for display; falls back to raw hex if encoding fails.
	def order_npub(pubkey)
		Nostr::Bech32.npub_encode(pubkey)
	rescue StandardError
		pubkey
	end
end
