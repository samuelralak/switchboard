# frozen_string_literal: true

require "test_helper"

module Orders
	module Ui
		class LifecycleTest < ActiveSupport::TestCase
			test "awaiting_funding: the chain is the four happy nodes, only the first current" do
				nodes = Orders::Ui::Lifecycle.nodes(order: build_order)

				assert_equal %w[awaiting_funding funded delivered released], nodes.map(&:key)
				assert_equal %w[current future future future], nodes.map(&:status)
			end

			test "awaiting_funding owns the funding-window countdown" do
				node = Orders::Ui::Lifecycle.nodes(order: build_order).first

				assert_equal "funding window", node.countdown[:label]
			end

			test "funded without a delivery: funded is current" do
				order = funded(build_order)

				assert_equal %w[done current future future], Orders::Ui::Lifecycle.nodes(order:).map(&:status)
			end

			test "funded with a delivery: delivered is current" do
				order = funded(build_order)
				Orders::MarkDelivered.call(order:, delivery_event_id: SecureRandom.hex(32),
					delivered_at: Time.current.to_i, content_hash: SecureRandom.hex(32))

				assert_equal %w[done done current future], Orders::Ui::Lifecycle.nodes(order:).map(&:status)
			end

			test "delivered then released: released is current and reads as awaiting redemption" do
				order = funded(build_order)
				deliver(order)
				release(order)
				nodes = Orders::Ui::Lifecycle.nodes(order:)

				assert_equal %w[done done done current], nodes.map(&:status), "current_state stays funded; released is current"
				assert_equal "Released, awaiting redemption", nodes.last.label
				assert_equal order.release.released_at.to_i, nodes.last.at.to_i
			end

			test "a release WITHOUT a delivery does not advance past funded (no false delivered step)" do
				order = funded(build_order)
				release(order)
				nodes = Orders::Ui::Lifecycle.nodes(order:)
				delivered = nodes.find { |node| node.key == Orders::Ui::Lifecycle::DELIVERED }

				assert_equal %w[done current future future], nodes.map(&:status), "no delivery -> funded stays current"
				assert_equal "future", delivered.status, "the delivered step is not marked done without a delivery"
				assert_nil delivered.at
			end

			test "refunded after a delivery and a release: the chain truncates to a refunded fault" do
				order = funded(build_order)
				deliver(order)
				release(order)
				order.state_machine.transition_to!(Orders::States::REFUNDED)
				nodes = Orders::Ui::Lifecycle.nodes(order:)

				assert_equal %w[awaiting_funding funded delivered refunded], nodes.map(&:key)
				assert_equal %w[done done done fault], nodes.map(&:status)
			end

			test "released: the chain is done with the last node settled" do
				order = funded(build_order)
				order.state_machine.transition_to!(Orders::States::RELEASED)

				assert_equal %w[done done done settled], Orders::Ui::Lifecycle.nodes(order:).map(&:status)
			end

			test "expired: a fault terminal off awaiting_funding" do
				order = build_order
				order.state_machine.transition_to!(Orders::States::EXPIRED)

				pairs = Orders::Ui::Lifecycle.nodes(order:).map { |node| [ node.key, node.status ] }

				assert_equal [ %w[awaiting_funding done], %w[expired fault] ], pairs
			end

			test "refunded: a fault terminal off funded" do
				order = funded(build_order)
				order.state_machine.transition_to!(Orders::States::REFUNDED)
				nodes = Orders::Ui::Lifecycle.nodes(order:)

				assert_equal %w[awaiting_funding funded refunded], nodes.map(&:key)
				assert_equal %w[done done fault], nodes.map(&:status)
			end

			private

			def funded(order)
				order.state_machine.transition_to!(Orders::States::FUNDED)
				order
			end

			def deliver(order)
				Orders::MarkDelivered.call(order:, delivery_event_id: SecureRandom.hex(32),
					delivered_at: Time.current.to_i, content_hash: SecureRandom.hex(32))
			end

			def release(order)
				Orders::MarkReleased.call(order:, reveal_event_id: SecureRandom.hex(32), released_at: Time.current.to_i)
			end
		end
	end
end
