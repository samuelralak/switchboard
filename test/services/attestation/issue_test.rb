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

		test "attestation is strict on the event id: a different event is not attested" do
			Issue.call(event: service_listing, manager: fake_manager)

			assert_not Catalog::Listing.new(service_listing).attested?, "a different listing is not covered"
		end

		test "a label in another env's namespace is not counted as attested" do
			listing = service_listing
			issuer_label(listing, namespace: Attestation::NAMESPACE_BASE)

			assert_not Catalog::Listing.new(listing).attested?, "a prod-namespace label must not validate off prod"
		end

		test "the attested_by scope selects attested events, rejecting bare and wrong-namespace labels" do
			attested = service_listing
			bare = service_listing
			wrong_ns = service_listing
			Issue.call(event: attested, manager: fake_manager)
			issuer_label(wrong_ns, namespace: Attestation::NAMESPACE_BASE)

			scoped = Event.attested_by(Attestation::Policy.issuer_pubkey)

			assert_includes scoped, attested
			assert_not_includes scoped, bare
			assert_not_includes scoped, wrong_ns
		end

		private

		def service_listing
			build_event(extra_tags: [ [ "t", Catalog::Listing.marker ], %w[price 1500 sat] ])
		end

		def open_request
			build_event(extra_tags: [ [ "t", Requests::OpenRequest.marker ] ])
		end

		def fake_manager
			manager = Object.new
			manager.define_singleton_method(:publish) { |_event| [ :ok ] }
			manager
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

		def with_policy(value)
			previous = Attestation::Policy.config.policy
			Attestation::Policy.config.policy = value
			yield
		ensure
			Attestation::Policy.config.policy = previous
		end
	end
end
