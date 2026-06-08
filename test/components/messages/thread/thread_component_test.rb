# frozen_string_literal: true

require "test_helper"

module Messages
	module Thread
		class ThreadComponentTest < ViewComponent::TestCase
			test "an unfunded order offers the provider no action: the client must fund first" do
				order = build_order(provider_pubkey: provider)

				render_inline(ThreadComponent.new(conversation: conversation_for(order)))

				assert_text "New request"
				assert_no_text "Accept"
				assert_no_link href: order_path(order.id)
			end

			test "a funded order links the provider into the order page to deliver" do
				order = funded(build_order(provider_pubkey: provider))

				render_inline(ThreadComponent.new(conversation: conversation_for(order)))

				assert_text "Awaiting your delivery"
				assert_link "Open order to deliver", href: order_path(order.id)
			end

			test "a delivered order shows the awaiting-release status and links to the order" do
				order = funded(build_order(provider_pubkey: provider))
				Orders::MarkDelivered.call(order:, delivery_event_id: SecureRandom.hex(32),
					delivered_at: Time.current.to_i, content_hash: SecureRandom.hex(32))

				render_inline(ThreadComponent.new(conversation: conversation_for(order)))

				assert_text "Delivered, awaiting release"
				assert_link "Open order", href: order_path(order.id)
			end

			test "a completed order links the provider to view the order" do
				order = funded(build_order(provider_pubkey: provider))
				order.state_machine.transition_to!(Orders::States::RELEASED)

				render_inline(ThreadComponent.new(conversation: conversation_for(order)))

				assert_text "Completed"
				assert_link "View order", href: order_path(order.id)
			end

			private

			def provider = @provider ||= SecureRandom.hex(32)
			# The thread's order actions open the order drawer over the thread (?order_id), not the bare page.
			def order_path(id) = Rails.application.routes.url_helpers.message_path(id, order_id: id)

			def conversation_for(order)
				Messages::ProviderInbox.call(pubkey: provider).find { |c| c.id == order.id }
			end

			def funded(order)
				order.state_machine.transition_to!(Orders::States::FUNDED)
				order
			end
		end
	end
end
