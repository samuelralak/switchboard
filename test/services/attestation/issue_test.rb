# frozen_string_literal: true

require "test_helper"

module Attestation
	# The issuance + read path: a signed kind-1985 label makes a service listing or open request read as
	# attested, idempotently, and only when the policy is on.
	class IssueTest < ActiveSupport::TestCase
		test "attesting a service listing makes the catalog read it as attested" do
			listing = service_listing
			assert_not Catalog::Listing.new(listing).attested?, "fresh listing should not be attested"

			Issue.call(event: listing, manager: fake_manager)

			assert Catalog::Listing.new(listing).attested?, "listing should read as attested after issuance"
		end

		test "attesting an open request makes the board read it as attested" do
			request = open_request

			Issue.call(event: request, manager: fake_manager)

			assert Requests::OpenRequest.new(request).attested?, "request should read as attested after issuance"
		end

		test "issuance is idempotent per event id" do
			listing = service_listing

			assert Issue.call(event: listing, manager: fake_manager), "first issue should produce a label"
			assert_nil Issue.call(event: listing, manager: fake_manager), "re-issue for the same event is a no-op"
		end

		test "the off policy issues nothing and reads not-attested" do
			listing = service_listing

			with_policy("off") do
				assert_nil Issue.call(event: listing, manager: fake_manager)
				assert_not Catalog::Listing.new(listing).attested?
			end
		end

		test "a broadcast failure still stores the label locally and does not raise" do
			listing = service_listing
			no_connections = Object.new
			no_connections.define_singleton_method(:publish) { |_event| raise NostrClient::Error, "no relay connections in this process" }

			assert_nothing_raised { Issue.call(event: listing, manager: no_connections) }
			assert Catalog::Listing.new(listing).attested?, "the label must be stored locally even when the relay broadcast fails"
		end

		test "the fee gate is a pass-through for now: attestation issues even when a fee is required" do
			listing = service_listing

			with_require_fee do
				assert Issue.call(event: listing, manager: fake_manager), "the fee gate must not block issuance yet"
				assert Catalog::Listing.new(listing).attested?
			end
		end

		test "attestation is strict on the event id: a different event is not attested" do
			Issue.call(event: service_listing, manager: fake_manager)

			assert_not Catalog::Listing.new(service_listing).attested?, "a different listing is not covered"
		end

		test "a label in another env's namespace is not counted as attested" do
			listing = service_listing
			issuer_label(listing, namespace: Attestation::NAMESPACE_BASE)

			assert_not Catalog::Listing.new(listing).attested?, "a prod-namespace label must not validate off prod"
		end

		private

		# Turn the fee gate on at the config layer (mirrors with_policy), then restore.
		def with_require_fee
			previous = Attestation::Policy.config.require_fee
			Attestation::Policy.config.require_fee = true
			yield
		ensure
			Attestation::Policy.config.require_fee = previous
		end

		def service_listing
			build_event(extra_tags: [ [ "t", Catalog::Listing.marker ], %w[price 1500 sat] ])
		end

		def open_request
			build_event(extra_tags: [ [ "t", Requests::OpenRequest.marker ] ])
		end

		# An issuer-signed "listed" label for `event` stamped with an arbitrary namespace, persisted directly so a
		# test can pin a non-current namespace the read path must reject.
		def issuer_label(event, namespace:)
			tags = [ [ "L", namespace ], [ "l", Attestation::LABEL_VALUE, namespace ], [ "e", event.event_id ] ]
			Event.create!(
				event_id: SecureRandom.hex(32),
				pubkey: Attestation::Policy.issuer_pubkey,
				sig: SecureRandom.hex(64),
				kind: Events::Kinds::LABEL,
				content: "",
				tags:,
				nostr_created_at: Time.current,
				raw_event: { "id" => SecureRandom.hex(32) }
			)
		end
	end
end
