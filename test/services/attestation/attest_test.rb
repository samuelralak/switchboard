# frozen_string_literal: true

require "test_helper"

module Attestation
	# The interim trigger: a provider reports a publish and the platform attests it, but only their OWN
	# conforming kind-30402. Verifies the ownership + conformance gates.
	class AttestTest < ActiveSupport::TestCase
		test "attests a conforming listing reported by its author" do
			keypair = Nostr::Keygen.new.generate_key_pair
			event = signed_listing(keypair.private_key.to_s)

			Attest.call(event_data: event, reporter_pubkey: keypair.public_key.to_s, manager: fake_manager)

			stored = Event.find_by(event_id: event["id"])
			assert stored, "the reported listing should be stored"
			assert Catalog::Listing.new(stored).attested?, "the reported listing should be attested"
		end

		test "does not attest a listing reported by someone other than its author" do
			keypair = Nostr::Keygen.new.generate_key_pair
			event = signed_listing(keypair.private_key.to_s)

			assert_nil Attest.call(event_data: event, reporter_pubkey: "f" * 64, manager: fake_manager)
			assert_nil Event.find_by(event_id: event["id"]), "a non-owner report stores nothing"
		end

		test "does not attest a non-conforming (unmarked) event" do
			keypair = Nostr::Keygen.new.generate_key_pair
			priv = keypair.private_key.to_s
			tags = [ [ "d", SecureRandom.hex(4) ], %w[title X] ]
			event = Events::Sign.call(private_key: priv, kind: Events::Kinds::CLASSIFIED, content: "x", tags:)

			Attest.call(event_data: event, reporter_pubkey: keypair.public_key.to_s, manager: fake_manager)

			assert_not Catalog::Listing.new(Event.find_by(event_id: event["id"])).attested?
		end

		private

		def signed_listing(private_key)
			tags = [ [ "d", SecureRandom.hex(4) ], %w[title Svc], %w[price 1500 sat], [ "t", Catalog::Listing.marker ] ]
			Events::Sign.call(private_key:, kind: Events::Kinds::CLASSIFIED, content: "svc", tags:)
		end
	end
end
