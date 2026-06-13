# frozen_string_literal: true

require "test_helper"

module Requests
	module Ui
		# The demand-side mirror of Catalog::Ui::Update, carrying the same takedown-critical flagged gate.
		class UpdateTest < ActiveSupport::TestCase
			def request_event(extra_tags: [], **)
				build_event(extra_tags: [ [ "t", OpenRequest.marker ], *extra_tags ], **)
			end

			test "an open request broadcasts remove (card + drawer) then re-adds the card and its drawer" do
				event = request_event(title: "Need a logo", d: "logo")

				actions = recording_turbo_actions { Requests::Ui::Update.call(event:) }

				assert_equal %i[broadcast_remove_to broadcast_remove_to broadcast_prepend_to broadcast_append_to],
					actions.map(&:first)
			end

			test "a withdrawn (inactive) request is remove-only: card + drawer removed, nothing re-added" do
				event = request_event(title: "Withdrawn", d: "off", extra_tags: [ %w[status inactive] ])

				actions = recording_turbo_actions { Requests::Ui::Update.call(event:) }

				assert_equal %i[broadcast_remove_to broadcast_remove_to], actions.map(&:first)
			end

			test "an operator-flagged author's open request is remove-only (takedown beats the live broadcast)" do
				event = request_event(title: "Spam", d: "spam")
				User.create!(pubkey: event.pubkey, first_seen_at: Time.current, flagged: true)

				actions = recording_turbo_actions { Requests::Ui::Update.call(event:) }

				assert_equal %i[broadcast_remove_to broadcast_remove_to], actions.map(&:first)
			end

			test "visible: false forces remove-only (a deleted request dropping off open boards)" do
				event = request_event(title: "Gone", d: "gone")

				actions = recording_turbo_actions { Requests::Ui::Update.call(event:, visible: false) }

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
