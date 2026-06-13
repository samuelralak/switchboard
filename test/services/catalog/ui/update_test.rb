# frozen_string_literal: true

require "test_helper"

module Catalog
	module Ui
		class UpdateTest < ActiveSupport::TestCase
			test "an active listing broadcasts remove (card + drawer) then re-adds the card and its drawer" do
				event = build_event(title: "Logo design", d: "logo")

				actions = recording_turbo_actions { Catalog::Ui::Update.call(event:) }

				assert_equal %i[broadcast_remove_to broadcast_remove_to broadcast_prepend_to broadcast_append_to],
										actions.map(&:first)
			end

			test "an unpublished (inactive) listing is remove-only: card + drawer removed, nothing re-added" do
				event = build_event(title: "Unpublished", d: "off", extra_tags: [ %w[status inactive] ])

				actions = recording_turbo_actions { Catalog::Ui::Update.call(event:) }

				assert_equal %i[broadcast_remove_to broadcast_remove_to], actions.map(&:first)
			end

			test "an operator-flagged author's active listing is remove-only (takedown beats the live broadcast)" do
				event = build_event(title: "Scam", d: "scam")
				User.create!(pubkey: event.pubkey, first_seen_at: Time.current, flagged: true)

				actions = recording_turbo_actions { Catalog::Ui::Update.call(event:) }

				assert_equal %i[broadcast_remove_to broadcast_remove_to], actions.map(&:first)
			end

			test "visible: false forces remove-only (a deleted listing dropping off open boards)" do
				event = build_event(title: "Gone", d: "gone")

				actions = recording_turbo_actions { Catalog::Ui::Update.call(event:, visible: false) }

				assert_equal %i[broadcast_remove_to broadcast_remove_to], actions.map(&:first)
			end

			private

			# Record the Turbo stream actions Update.call issues, without broadcasting.
			def recording_turbo_actions
				actions = []
				channel = Turbo::StreamsChannel.singleton_class
				%i[broadcast_remove_to broadcast_prepend_to broadcast_append_to].each do |name|
					channel.send(:alias_method, "__orig_#{name}", name)
					channel.send(:define_method, name) { |stream, **| actions << [ name, stream ] }
				end
				yield
				actions
			ensure
				%i[broadcast_remove_to broadcast_prepend_to broadcast_append_to].each do |name|
					channel.send(:alias_method, name, "__orig_#{name}")
					channel.send(:remove_method, "__orig_#{name}")
				end
			end
		end
	end
end
