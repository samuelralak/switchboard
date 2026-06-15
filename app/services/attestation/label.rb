# frozen_string_literal: true

module Attestation
	# Builds the tag set for a kind-1985 NIP-32 label that vouches for a listing: the namespaced "listed" label
	# plus the targets. The `a` tag pins the stable coordinate (kind:pubkey:d); the `e` tag pins the EXACT
	# attested event id, so an edit (a new event at the same coordinate) is not silently covered by an old label.
	class Label < BaseService
		option :coordinate, type: Types::Strict::String
		option :event_id, type: Types::Strict::String
		option :namespace, type: Types::Strict::String, default: -> { Policy.namespace }

		def call
			[ [ "L", namespace ], [ "l", LABEL_VALUE, namespace ], [ "a", coordinate ], [ "e", event_id ] ]
		end
	end
end
