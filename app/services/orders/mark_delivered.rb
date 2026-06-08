# frozen_string_literal: true

module Orders
	# Record the provider's observable assertion that they delivered the result: the delivery gift-wrap event
	# id, its timestamp, and a content-hash commitment. Stores ONLY observable data (brief 6.3); the result
	# itself travels end-to-end over NIP-17 and is never seen by the runtime. Provider-only; the order must be
	# funded. current_state STAYS funded -- this deliberately does NOT touch the state machine, so the
	# settlement/refund mechanics, the active-order indexes, and the reconcile sweep are all unchanged. A
	# re-delivery supersedes the prior assertion (UNIQUE(order_id)).
	class MarkDelivered < BaseService
		option :order
		option :delivery_event_id, type: Types::Strict::String
		option :delivered_at
		option :content_hash, type: Types::Strict::String

		def call
			ensure_funded!
			Order.transaction do |txn|
				record!
				# Flip the live status strip to "Delivered, awaiting release" on both parties' open pages, after
				# commit, mirroring Orders::Transition.
				txn.after_commit { Orders::Ui::Update.call(order:) }
			end
			order.delivery
		end

		private

		def ensure_funded!
			return if order.current_state == Orders::States::FUNDED

			raise IllegalTransitionError, "cannot deliver a #{order.current_state} order"
		end

		# Upsert the single delivery row; a re-delivery overwrites it with the newer wrap (supersede).
		def record!
			delivery = order.delivery || order.build_delivery
			delivery.update!(delivery_event_id:, delivered_at: delivered_at_time, content_hash:)
		end

		# delivered_at arrives as a Time (Ruby callers) or unix-seconds (the browser sends the rumor created_at).
		def delivered_at_time
			@delivered_at_time ||= unix_time? ? Time.at(delivered_at.to_i).utc : delivered_at
		end

		def unix_time? = delivered_at.is_a?(Numeric) || delivered_at.to_s.match?(/\A\d+\z/)
	end
end
