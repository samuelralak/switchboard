# frozen_string_literal: true

module Notifications
	# Records one recipient-addressed notification (a read-model projection of a server-observable event).
	# Callers fire this from an after_commit alongside the domain write, so it is a pure observer and never
	# mutates domain state. The live broadcast to the recipient's stream lands with the bell UI (a later slice);
	# this slice persists the row, which the bell renders on load.
	class Deliver < BaseService
		option :recipient_pubkey, type: Types::Strict::String
		option :notification_type, type: Types::Strict::String
		option :metadata, type: Types::Strict::Hash, default: -> { {} }

		def call
			Notification.create!(recipient_pubkey:, notification_type:, metadata:)
		end
	end
end
