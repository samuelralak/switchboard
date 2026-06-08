# frozen_string_literal: true

module Orders
	module Lifecycle
		# The order's lifecycle stepper: a segmented progress strip + a vertical node timeline (lamp,
		# connector, label, timestamp, note, live countdown), over our real states only. The order page's
		# primary state surface and the Turbo broadcast target. Node derivation lives in Orders::Ui::Lifecycle;
		# this component just renders. Labels are sans (prose); mono is reserved for the timestamps/countdowns.
		class LifecycleComponent < ApplicationComponent
			# Node status -> the design tokens for the lamp, the connector, and the segmented strip. The five
			# states port the prototype's lamp/connector language 1:1 onto our tokens.
			LAMP = {
				"current" => "size-2.5 bg-lamp-live shadow-lamp motion-safe:animate-pulse",
				"done" => "size-2 bg-copper",
				"settled" => "size-2.5 bg-lamp-settled",
				"fault" => "size-2.5 bg-lamp-fault",
				"future" => "size-2 border border-border-strong"
			}.freeze

			CONNECTOR = {
				"done" => "bg-copper-dim/60", "settled" => "bg-copper-dim/60", "current" => "bg-copper-dim/30"
			}.freeze
			STRIP = {
				"current" => "bg-lamp-live", "done" => "bg-copper", "settled" => "bg-lamp-settled",
				"fault" => "bg-lamp-fault", "future" => "bg-border-strong"
			}.freeze

			LABEL_TONE = {
				"future" => "text-ink-faint", "fault" => "text-lamp-fault", "current" => "text-lamp-live"
			}.freeze

			attr_reader :order

			def initialize(order:)
				@order = order
			end

			def dom_id = Orders::Ui::State.lifecycle(order:).target
			def nodes = @nodes ||= Orders::Ui::Lifecycle.nodes(order:)

			def lamp(status) = LAMP.fetch(status, LAMP["future"])
			def connector(status) = CONNECTOR.fetch(status, "bg-border-strong")
			def strip(status) = STRIP.fetch(status, STRIP["future"])
			def label_tone(status) = LABEL_TONE.fetch(status, "text-ink")

			# The headline state chip (tone + label), from the consumer's side. One glance answers "where's
			# my money": awaiting -> live, in escrow -> copper, released -> settled, refund/expiry -> fault.
			CHIP = {
				Orders::States::AWAITING_FUNDING => { tone: :live, label: "awaiting funding" },
				Orders::States::FUNDED => { tone: :copper, label: "in escrow" },
				Orders::States::RELEASED => { tone: :settled, label: "released" },
				Orders::States::REFUNDED => { tone: :fault, label: "refunded" },
				Orders::States::EXPIRED => { tone: :fault, label: "expired" }
			}.freeze

			def chip_tone = chip[:tone]
			def chip_label = chip[:label]

			# Funded but the consumer has revealed the preimage: the headline reads "releasing" to match the
			# timeline's released-awaiting-redemption node, while current_state is still funded.
			def chip
				return { tone: :copper, label: "releasing" } if releasing?

				CHIP.fetch(order.current_state, { tone: :neutral, label: order.current_state })
			end

			# Matches Orders::Ui::Lifecycle#current_node: a release reflects only once a delivery is recorded.
			def releasing?
				order.current_state == Orders::States::FUNDED && order.release.present? && order.delivery.present?
			end

			# Notes earn their space only on the active step and the terminal/fault outcome; a finished step's
			# instructions are noise.
			def note?(node) = node.note && %w[current settled fault].include?(node.status)
		end
	end
end
