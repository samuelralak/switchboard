# frozen_string_literal: true

module Messages
	module Thread
		# The detail pane from the provider's side: who sent the request and their track
		# record, the service and the filled schema, the escrow that releases to you, your
		# delivery, and the one decision the current state calls for. Never free-form chat.
		class ThreadComponent < ApplicationComponent
			# state -> the status strip's signal: tone (drives band/lamp/text), label, and
			# whether the lamp pulses (only states with a live clock the provider owns).
			STATUS = {
				received: { tone: :copper, label: "New request", pulse: false },
				accepted: { tone: :live, label: "Accepted", pulse: true },
				awaiting_fulfillment: { tone: :live, label: "Awaiting your delivery", pulse: true },
				verifying_delivery: { tone: :copper, label: "Delivered, verifying", pulse: false },
				completed: { tone: :settled, label: "Completed", pulse: false },
				expired: { tone: :fault, label: "Expired, not delivered", pulse: false },
				failed: { tone: :fault, label: "Failed", pulse: false },
				refunded: { tone: :fault, label: "Refunded", pulse: false },
				cancelled: { tone: :muted, label: "Cancelled", pulse: false }
			}.freeze

			FALLBACK_STATUS = { tone: :muted, label: "Pending", pulse: false }.freeze

			# tone -> the strip's tinted band, lamp, and text classes (mirrors Shared::Alert).
			TONE = {
				copper: { band: "border-copper-dim/40 bg-copper/5", lamp: "bg-copper", text: "text-copper" },
				live: { band: "border-lamp-live/30 bg-lamp-live/5", lamp: "bg-lamp-live", text: "text-lamp-live" },
				settled: { band: "border-lamp-settled/40 bg-lamp-settled/5",
					lamp: "bg-lamp-settled", text: "text-lamp-settled" },
				fault: { band: "border-lamp-fault/40 bg-lamp-fault/5", lamp: "bg-lamp-fault", text: "text-lamp-fault" },
				muted: { band: "border-border bg-surface", lamp: "bg-ink-faint", text: "text-ink-muted" }
			}.freeze

			attr_reader :conversation

			def initialize(conversation:)
				@conversation = conversation
			end

			def status = STATUS.fetch(conversation.state, FALLBACK_STATUS)
			def tone = TONE.fetch(status[:tone], TONE[:muted])

			# Escrow terms by fulfillment mode, framed for the provider (the money comes to you).
			def escrow_terms
				if conversation.automated?
					[ [ "Mechanism", "Lightning hold invoice" ], [ "Releases", "to you on a valid response" ],
						[ "If undelivered", "auto-cancelled, refunded to the client" ] ]
				else
					[ [ "Mechanism", "key-locked Cashu ecash" ], [ "Releases", "to you when the client approves" ],
						[ "If undelivered", "refunds to the client after #{conversation.span}" ] ]
				end
			end

			# The state -> the typed actions available now (label, button variant, icon).
			def actions
				case conversation.state
				when :received
					[ { label: "Accept request", variant: :primary, icon: "tick-02" },
						{ label: "Decline", variant: :ghost, icon: "cancel-01" } ]
				when :accepted, :awaiting_fulfillment
					[ { label: "Submit delivery", variant: :primary, icon: "sent" },
						{ label: "Request extension", variant: :ghost, icon: "clock-01" } ]
				when :completed
					[ { label: "View delivered result", variant: :ghost, icon: "download-01" } ]
				else
					[]
				end
			end
		end
	end
end
