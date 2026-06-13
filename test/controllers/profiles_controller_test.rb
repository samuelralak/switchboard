# frozen_string_literal: true

require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
	def npub_for(hex) = Nostr::Bech32.npub_encode(hex)

	def listing_event(pubkey:, d_tag:, title:)
		Event.create!(
			event_id: SecureRandom.hex(32), pubkey:, sig: SecureRandom.hex(64), kind: Events::Kinds::CLASSIFIED,
			content: title, nostr_created_at: Time.current, raw_event: { "id" => SecureRandom.hex(32) },
			tags: [ [ "d", d_tag ], [ "title", title ], [ "t", Catalog::Listing.marker ], %w[price 2000 sat] ]
		)
	end

	test "renders a known provider's identity from their kind-0 projection" do
		user = User.create!(pubkey: SecureRandom.hex(32), first_seen_at: Time.current,
			display_name: "Apollo", name: "apollo", nip05: "apollo@example.com")

		get profile_url(npub: npub_for(user.pubkey))

		assert_response :success
		assert_select "h1", text: "Apollo"
		assert_includes response.body, "apollo@example.com"
		assert_includes response.body, user.npub.truncate(24, omission: "…") # the npub (mono)
	end

	test "shows the provider's live services as cards that mount their order drawers" do
		user = User.create!(pubkey: SecureRandom.hex(32), first_seen_at: Time.current, display_name: "Apollo")
		listing_event(pubkey: user.pubkey, d_tag: "logo", title: "Logo design") # active (no status tag)

		get profile_url(npub: npub_for(user.pubkey))

		assert_response :success
		assert_includes response.body, "Logo design"
		assert_select "##{Catalog::Ui::State::DRAWER_TARGET}" # the order-drawer mount
	end

	test "shows an empty services state when the provider has none live" do
		user = User.create!(pubkey: SecureRandom.hex(32), first_seen_at: Time.current, display_name: "Apollo")

		get profile_url(npub: npub_for(user.pubkey))

		assert_response :success
		assert_includes response.body, "No services yet"
	end

	test "a malformed or non-npub identifier 404s" do
		get profile_url(npub: "not-a-valid-npub")

		assert_response :not_found
	end

	test "a valid but unindexed npub shows a placeholder and enqueues a kind-0 fetch (no 404)" do
		hex = SecureRandom.hex(32)
		calls = []
		Users::MetadataFetchJob.define_singleton_method(:perform_later) { |*args, **kwargs| calls << [ args, kwargs ] }

		get profile_url(npub: npub_for(hex))

		assert_response :success
		assert_includes response.body, "Fetching this profile"
		assert_equal [ [ [ hex ], { force: true } ] ], calls
	ensure
		Users::MetadataFetchJob.singleton_class.send(:remove_method, :perform_later)
	end
end
