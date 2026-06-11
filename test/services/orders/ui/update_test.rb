# frozen_string_literal: true

require "test_helper"

module Orders
	module Ui
		class UpdateTest < ActiveSupport::TestCase
			test "broadcasts the status strip and a detail-frame reload to the order's own stream" do
				order = build_order
				strip = Orders::Ui::State.strip(order:)
				detail = Orders::Ui::State.detail(order:)

				actions = recording_turbo_actions { Orders::Ui::Update.call(order:) }

				# detail re-fetches the frame so each viewer re-renders its own action panels (strip stays for the
				# compact form on other surfaces).
				assert_equal [ [ strip.stream, strip.target ], [ detail.stream, detail.target ] ], actions
			end

			private

			# Record the Turbo stream + target Update.call issues, without broadcasting.
			def recording_turbo_actions
				actions = []
				channel = Turbo::StreamsChannel.singleton_class
				channel.send(:alias_method, :__orig_broadcast_replace_to, :broadcast_replace_to)
				channel.send(:define_method, :broadcast_replace_to) { |stream, **opts| actions << [ stream, opts[:target] ] }
				yield
				actions
			ensure
				channel.send(:alias_method, :broadcast_replace_to, :__orig_broadcast_replace_to)
				channel.send(:remove_method, :__orig_broadcast_replace_to)
			end
		end
	end
end
