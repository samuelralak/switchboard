# frozen_string_literal: true

require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
	def npub_for(hex) = Nostr::Bech32.npub_encode(hex)

	test "renders a known provider's identity from their kind-0 projection" do
		user = User.create!(pubkey: SecureRandom.hex(32), first_seen_at: Time.current,
			display_name: "Apollo", name: "apollo", nip05: "apollo@example.com")

		get profile_url(npub: npub_for(user.pubkey))

		assert_response :success
		assert_select "h1", text: "Apollo"
		assert_includes response.body, "apollo@example.com"
		assert_includes response.body, user.npub.truncate(24, omission: "…") # the npub (mono)
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
