# frozen_string_literal: true

module Notifications
	# Maps a server-observable order event to the recipient-addressed notification(s) it warrants and records
	# them via Notifications::Deliver. The single home for "which party hears about which order event". A pure
	# OBSERVER, fired from the lifecycle hooks' after_commit; any failure here is reported and swallowed so a
	# notification bug can NEVER break order processing (the money path has already committed).
	class ForOrder < BaseService
		option :order
		option :event, type: Types::Coercible::Symbol

		def call
			recipients.each do |pubkey|
				Notifications::Deliver.call(recipient_pubkey: pubkey, notification_type:, metadata:)
			end
		rescue StandardError => e
			Rails.error.report(e, handled: true, context: { order_id: order.id, event: })
			nil
		end

		private

		# The party/parties who hear about this event -- always the side that did NOT cause it (both for a
		# settlement). A catalog order placed is silent (the provider hears at funding); a request CLAIM alerts
		# the requester who posted it. funded + release_authorized both prompt the provider (deliver / redeem).
		def recipients
			consumer = order.consumer_pubkey
			provider = order.provider_pubkey
			case event
			when :placed then request_claim? ? [ consumer ] : []
			when :funded, :release_authorized then [ provider ]
			when :delivered, :released then [ consumer ]
			when :refunded, :expired then [ consumer, provider ].uniq
			else []
			end
		end

		def request_claim? = order.entry_point == Orders::EntryPoints::REQUEST_CLAIM

		def notification_type = event == :placed ? "request_claimed" : "order_#{event}"

		def metadata
			{
				"order_id" => order.id,
				"entry_point" => order.entry_point,
				"amount_sats" => order.amount_sats,
				"listing_coordinate" => order.listing_coordinate
			}
		end
	end
end
