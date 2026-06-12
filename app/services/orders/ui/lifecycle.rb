# frozen_string_literal: true

module Orders
	module Ui
		# The order lifecycle as a chain of nodes for the stepper, derived ONLY from our real states + the
		# delivery assertion. Happy path: awaiting_funding -> funded -> delivered -> released; a fault (expired
		# off awaiting_funding, refunded off funded) replaces the tail. Each node carries its status (the
		# prototype's done/current/future/settled/fault vocabulary), a timestamp, a note, and any live
		# countdown. A composer so the component stays a thin presenter (mirrors Orders::Ui::State).
		class Lifecycle
			S = Orders::States
			# "delivered" is the only non-state node (the order.delivery assertion); it sits between funded and
			# released and renders future until a delivery exists.
			DELIVERED = "delivered"
			# "disputed" is a real state (S::DISPUTED) but renders as its own terminal-ish node off funded.
			DISPUTED = "disputed"
			CHAIN = [ S::AWAITING_FUNDING, S::FUNDED, DELIVERED, S::RELEASED ].freeze

			LABELS = {
				S::AWAITING_FUNDING => "Awaiting funding", S::FUNDED => "Funded, in escrow",
				DELIVERED => "Delivered, awaiting release", S::RELEASED => "Released to provider",
				S::REFUNDED => "Refunded to you", S::EXPIRED => "Expired, unfunded", DISPUTED => "In dispute"
			}.freeze

			NOTES = {
				S::AWAITING_FUNDING => "Lock the budget in escrow to start the order. Until then nothing is committed.",
				S::FUNDED => "Funds lock as key-locked Cashu (NUT-11 P2PK) with a timelock refund. " \
					"Locked to keys, never held by us.",
				DELIVERED => "The provider delivered the finished work, sealed to you end to end. " \
					"Review it, then release the escrow.",
				S::RELEASED => "The escrow released to the provider. Money in, data out.",
				S::REFUNDED => "The escrow refunded to you after the lock expired without a release.",
				S::EXPIRED => "The funding window passed before the escrow was funded.",
				DISPUTED => "Escalated to the platform arbiter, who reviews it and co-signs the release to the ruled side."
			}.freeze

			Node = Data.define(:key, :label, :status, :at, :note, :countdown)

			def self.nodes(order:) = new(order).nodes

			def initialize(order)
				@order = order
			end

			def nodes
				case @order.current_state
				when S::RELEASED then released_chain
				when S::REFUNDED then fault_chain(S::REFUNDED)
				when S::EXPIRED  then fault_chain(S::EXPIRED)
				when S::DISPUTED then disputed_chain
				else active_chain
				end
			end

			private

			attr_reader :order

			# In-progress: the current node is released (consumer revealed, awaiting the provider's redemption),
			# else delivered (a delivery exists), else funded, else awaiting. current_state is still funded in
			# all of these; the released node only SETTLES once the mint confirms the spend (released_chain).
			def active_chain
				cut = CHAIN.index(current_node)

				CHAIN.each_with_index.map { |key, i| node(key, status_at(i, cut)) }
			end

			# A release advances the chain only once a delivery is recorded: a release presupposes the work was
			# received, so without a delivery the chain would mark "delivered" done for a step that never
			# happened. Until both exist, the chain stops at delivered (or funded).
			def current_node
				return S::RELEASED if order.release.present? && order.delivery.present?
				return DELIVERED if order.delivery.present?

				order.current_state == S::FUNDED ? S::FUNDED : S::AWAITING_FUNDING
			end

			def status_at(index, cut)
				return "done" if index < cut

				index == cut ? "current" : "future"
			end

			# Released is the happy terminal: the whole chain is done, the last node settled.
			def released_chain
				CHAIN.map { |key| node(key, key == S::RELEASED ? "settled" : "done") }
			end

			# A fault truncates the happy chain at the last reached node and appends the fault terminal.
			def fault_chain(state)
				reached = state == S::EXPIRED ? [ S::AWAITING_FUNDING ] : [ S::AWAITING_FUNDING, S::FUNDED ]
				reached << DELIVERED if state == S::REFUNDED && order.delivery.present?

				reached.map { |key| node(key, "done") } + [ node(state, "fault") ]
			end

			# A disputed order: the happy chain is done through funded (+ delivered if recorded), with a current
			# dispute node. The label/note reflect whether the arbiter has ruled yet; the order leaves this state
			# (to released/refunded) only once the on-mint spend settles it.
			def disputed_chain
				reached = [ S::AWAITING_FUNDING, S::FUNDED ]
				reached << DELIVERED if order.delivery.present?

				reached.map { |key| node(key, "done") } + [ node(DISPUTED, "current") ]
			end

			def node(key, status)
				Node.new(key:, label: label_for(key, status), status:, at: timestamp(key, status),
					note: note_for(key, status), countdown: countdown(key))
			end

			# The released node reads as authorized-but-pending while it is the current (not yet settled) node:
			# the consumer revealed, the provider has not redeemed yet.
			def label_for(key, status)
				return "Released, awaiting redemption" if key == S::RELEASED && status == "current"

				LABELS.fetch(key)
			end

			def note_for(key, status)
				if key == S::RELEASED && status == "current"
					return "You approved the release and revealed the secret to the provider. " \
						"The order settles to released once they redeem."
				end

				NOTES[key]
			end

			def timestamp(key, status)
				return if status == "future"

				assertion_time(key, status) || transitions[key]&.created_at
			end

			# Nodes timed by an observable assertion rather than a state transition: funding opens the order,
			# delivery + the current (not-yet-settled) release each carry their own timestamp.
			def assertion_time(key, status)
				case key
				when S::AWAITING_FUNDING then order.created_at
				when DELIVERED then order.delivery&.delivered_at
				when S::RELEASED then order.release&.released_at if status == "current"
				end
			end

			# The live deadline a node owns, if any: the funding window on awaiting_funding, the refund timelock
			# on funded (while the escrow is actually locked).
			def countdown(key)
				if key == S::AWAITING_FUNDING && order.current_state == S::AWAITING_FUNDING
					{ label: "funding window", at: order.funding_deadline_at, then: "order expires" }
				elsif key == S::FUNDED && order.current_state == S::FUNDED && order.lock&.locktime
					{ label: "timelock", at: order.lock.locktime, then: "refund available" }
				end
			end

			def transitions = @transitions ||= order.order_transitions.index_by(&:to_state)
		end
	end
end
