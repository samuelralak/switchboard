# frozen_string_literal: true

require "test_helper"

module Catalog
	module Ui
		class UpdateTest < ActiveSupport::TestCase
			test "broadcasts a remove then a prepend to the catalog stream" do
				event = build_event(title: "Logo design", d: "logo")

				actions = recording_turbo_actions { Catalog::Ui::Update.call(event:) }

				assert_equal [ [ :broadcast_remove_to, "catalog" ], [ :broadcast_prepend_to, "catalog" ] ], actions
			end

			private

			# Record the Turbo stream actions Update.call issues, without broadcasting.
			def recording_turbo_actions
				actions = []
				channel = Turbo::StreamsChannel.singleton_class
				%i[broadcast_remove_to broadcast_prepend_to].each do |name|
					channel.send(:alias_method, "__orig_#{name}", name)
					channel.send(:define_method, name) { |stream, **| actions << [ name, stream ] }
				end
				yield
				actions
			ensure
				%i[broadcast_remove_to broadcast_prepend_to].each do |name|
					channel.send(:alias_method, name, "__orig_#{name}")
					channel.send(:remove_method, "__orig_#{name}")
				end
			end
		end
	end
end
