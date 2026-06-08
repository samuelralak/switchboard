# frozen_string_literal: true

module Orders
	module Ui
		# Pushes an order's status strip to every open tracking page when its state changes. Triggered from
		# Orders::Transition's txn.after_commit, so it fires for both browser funding and the background
		# reconcile sweep (funded -> released/refunded/expired) without a page reload.
		class Update
			def self.call(order:)
				# The order page shows the lifecycle stepper; the strip is the compact form elsewhere. Both share
				# the order stream, so push both -- a replace whose target isn't on the open page is a harmless no-op.
				[ State.lifecycle(order:), State.strip(order:) ].each do |view|
					Turbo::StreamsChannel.broadcast_replace_to(view.stream, **view.broadcast)
				end
			end
		end
	end
end
