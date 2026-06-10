# frozen_string_literal: true

require "test_helper"

module Settings
	class ProfileControllerTest < ActionDispatch::IntegrationTest
		test "show and update require a signed-in session" do
			get settings_profile_url
			assert_redirected_to root_path

			patch settings_profile_url
			assert_redirected_to root_path
		end

		test "show renders the editor in the settings rail, prefilled from the user's projection" do
			sign_in
			User.find_by(pubkey: @session_pubkey).update!(display_name: "Ada Lovelace", name: "ada", nip05: "ada@example.com")

			get settings_profile_url

			assert_response :success
			assert_select "form#profile-form"
			assert_select "input[name=?][value=?]", "user[display_name]", "Ada Lovelace"
			assert_select "[data-field=?]", "picture"
			assert_select "a[href=?]", settings_relays_path # the shared rail links to the other sections
			assert_includes response.body, "Sign &amp; publish profile"
		end

		test "show carries the raw kind-0 as the merge base so unmanaged fields survive" do
			sign_in
			content = { "name" => "ada", "custom_field" => "keep me" }
			metadata_event(pubkey: @session_pubkey, content:, tags: [ %w[i github:ada proof] ])

			get settings_profile_url

			assert_response :success
			assert_includes response.body, "custom_field"
			assert_includes response.body, "github:ada"
		end

		test "update enqueues a forced metadata fetch and accepts" do
			sign_in
			calls = []
			Users::MetadataFetchJob.define_singleton_method(:perform_later) { |*args, **kwargs| calls << [ args, kwargs ] }

			patch settings_profile_url

			assert_response :accepted
			assert_equal [ [ [ @session_pubkey ], { force: true } ] ], calls
		ensure
			Users::MetadataFetchJob.singleton_class.send(:remove_method, :perform_later)
		end

		private

		def sign_in
			keypair = Nostr::Keygen.new.generate_key_pair
			@session_pubkey = keypair.public_key.to_s
			tags = nip98_tags(url: verify_url, challenge: LoginChallenge.issue.nonce)
			event = sign_event(kind: Events::Kinds::HTTP_AUTH, tags:, keypair:)
			post session_url, headers: { "Authorization" => "Nostr #{Base64.strict_encode64(JSON.generate(event))}" }
			assert_response :created
		end

		def metadata_event(pubkey:, content:, tags: [])
			Event.create!(
				event_id: SecureRandom.hex(32), pubkey:, sig: SecureRandom.hex(64),
				kind: Events::Kinds::METADATA, content: content.to_json, tags:,
				nostr_created_at: Time.current, raw_event: { "id" => SecureRandom.hex(32) }
			)
		end

		def verify_url = "#{Rails.application.config.x.canonical_origin}/session"
	end
end
