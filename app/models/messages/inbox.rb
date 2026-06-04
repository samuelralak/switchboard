# frozen_string_literal: true

module Messages
	# Placeholder inbox from the provider's perspective: incoming requests clients have sealed
	# to you over NIP-17, each joined to the targeted service. The gift-wrap decrypt layer
	# replaces .conversations later with the same Conversation/TrackRecord shapes.
	module Inbox
		CONVERSATIONS = [
			Conversation.new(
				id: "0x4a90b2", service: "Code review a snippet", cap: "code-review",
				description: "A senior engineer reviews the snippet for correctness, security, and clarity.",
				npub: "npub1bobqz7r3k", name: "bob",
				track: TrackRecord.new(completed: 0, settled: "0", since: "2026", disputes: 0, fresh: true),
				mode: "manual", sats: 5_000, span: "12h window", state: :received,
				created: "2m", deadline: nil, unread: true,
				note: "New request from bob. Accept to commit and start the 12h delivery clock.",
				inputs: [
					{ label: "Code (paste or url)", value: "https://gist.example/abc", type: "longtext", required: true },
					{ label: "Language", value: "Ruby", type: "text", required: true }
				],
				result: nil
			),
			Conversation.new(
				id: "0x9f3a21", service: "Translate EN ⇄ ES", cap: "translate",
				description: "A human translator preserving nuance, idiom, and tone.",
				npub: "npub1alice4w9p", name: "alice",
				track: TrackRecord.new(completed: 31, settled: "1.2M", since: "2024", disputes: 0, fresh: false),
				mode: "manual", sats: 1_500, span: "24h window", state: :awaiting_fulfillment,
				created: "1h", deadline: "03:58:12", unread: false,
				note: "You accepted. Deliver the translation before the timelock.",
				inputs: [
					{ label: "Source text", value: "Privacy is a practice, not a product.", type: "longtext", required: true },
					{ label: "Direction", value: "EN → ES", type: "text", required: true }
				],
				result: nil
			),
			Conversation.new(
				id: "0x7c14e8", service: "Proofread a long-form note", cap: "proofread",
				description: "Human proofreading for grammar, flow, and clarity, with tracked changes.",
				npub: "npub1carol8t0w", name: "carol",
				track: TrackRecord.new(completed: 12, settled: "480k", since: "2025", disputes: 1, fresh: false),
				mode: "manual", sats: 2_000, span: "8h window", state: :verifying_delivery,
				created: "3h", deadline: nil, unread: false,
				note: "Delivered. Awaiting carol's approval to release the escrow to you.",
				inputs: [
					{ label: "Draft", value: "A 1,200-word essay on key custody.", type: "longtext", required: true },
					{ label: "Style guide", value: "Plain, active voice.", type: "text", required: false }
				],
				result: "Returned with tracked changes: 14 edits. Tightened run-on sentences, fixed comma " \
					"splices, flagged 2 unclear claims."
			),
			Conversation.new(
				id: "0x22f7d1", service: "Translate EN ⇄ ES", cap: "translate",
				description: "A human translator preserving nuance, idiom, and tone.",
				npub: "npub1dave5xk2m", name: "dave",
				track: TrackRecord.new(completed: 58, settled: "3.1M", since: "2023", disputes: 0, fresh: false),
				mode: "manual", sats: 1_500, span: "24h window", state: :completed,
				created: "yesterday", deadline: nil, unread: false,
				note: "Approved and released. 1,500 sat settled to you.",
				inputs: [
					{ label: "Source text", value: "The cathedral and the bazaar.", type: "longtext", required: true },
					{ label: "Direction", value: "EN → ES", type: "text", required: true }
				],
				result: "Delivered the translation; the client approved and the escrow released."
			),
			Conversation.new(
				id: "0x18cc05", service: "Code review a snippet", cap: "code-review",
				description: "A senior engineer reviews the snippet for correctness, security, and clarity.",
				npub: "npub1erin9q4h2", name: "erin",
				track: TrackRecord.new(completed: 9, settled: "210k", since: "2025", disputes: 0, fresh: false),
				mode: "manual", sats: 5_000, span: "12h window", state: :expired,
				created: "2 days ago", deadline: nil, unread: false,
				note: "You missed the window. Escrow refunded to erin; a non-delivery was recorded against your npub.",
				inputs: [
					{ label: "Code (paste or url)", value: "https://gist.example/xyz", type: "longtext", required: true },
					{ label: "Language", value: "Go", type: "text", required: true }
				],
				result: nil
			)
		].freeze

		def self.conversations = CONVERSATIONS
	end
end
