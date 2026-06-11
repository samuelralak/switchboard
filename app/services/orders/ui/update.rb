# frozen_string_literal: true

module Orders
	module Ui
		# Pushes an order's status strip to every open tracking page when its state changes. Triggered from
		# Orders::Transition's txn.after_commit, so it fires for both browser funding and the background
		# reconcile sweep (funded -> released/refunded/expired) without a page reload.
		class Update
			def self.call(order:)
				# The strip is the compact status form on other surfaces. The detail re-fetches the order page's
				# frame so each viewer re-renders its OWN action panels (fund/release vs deliver/redeem) -- which a
				# single shared broadcast cannot do -- and it re-renders the lifecycle stepper too. Both share the
				# order stream; a replace whose target isn't on the open page is a harmless no-op.
				[ State.strip(order:), State.detail(order:) ].each do |view|
					Turbo::StreamsChannel.broadcast_replace_to(view.stream, **view.broadcast)
				end
			end
		end
	end
end
