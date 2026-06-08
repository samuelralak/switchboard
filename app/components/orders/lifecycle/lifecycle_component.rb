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

			# The money-in / data-out rail: the escrow's headline, framed from the consumer's side.
			def escrow_label
				case order.current_state
				when Orders::States::RELEASED then "released to the provider"
				when Orders::States::REFUNDED, Orders::States::EXPIRED then "refunded to you"
				when Orders::States::FUNDED then "#{number_with_delimiter(order.amount_sats)} sat locked"
				else "awaiting funding"
				end
			end

			# The funded node owns the timelock; while funded, the escrow is genuinely locked.
			def locked? = order.current_state == Orders::States::FUNDED
		end
	end
end
