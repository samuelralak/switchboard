# frozen_string_literal: true

module Catalog
	module ServiceDetail
		# Previews the externally-posted (non-Switchboard) gating: the author sees the republish path, everyone
		# else sees a disabled action with the reason. The hosted (orderable) variants are covered by tests.
		class ServiceDetailComponentPreview < ViewComponent::Preview
			def external_owner
				listing = external_listing
				render(ServiceDetailComponent.new(listing:, viewer: viewer(listing.event.pubkey)))
			end

			def external_visitor
				render(ServiceDetailComponent.new(listing: external_listing, viewer: viewer("f" * 64)))
			end

			private

			# A non-conforming (no Switchboard marker) NIP-99 listing, as it would arrive from the wider network.
			def external_listing
				tags = [ %w[d ext-preview], [ "title", "External translation service" ], %w[price 1500 sat] ]
				content = "A translation service posted on another Nostr app."
				event = Event.new(pubkey: "ab" * 32, kind: Events::Kinds::CLASSIFIED, content:, tags:)

				Catalog::Listing.new(event)
			end

			def viewer(pubkey) = Struct.new(:pubkey).new(pubkey)
		end
	end
end
