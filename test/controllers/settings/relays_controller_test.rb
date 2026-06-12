# frozen_string_literal: true

require "test_helper"

module Settings
	class RelaysControllerTest < ActionDispatch::IntegrationTest
		test "show and update require a signed-in session" do
			get settings_relays_url
			assert_redirected_to root_path

			patch settings_relays_url
			assert_redirected_to root_path
		end

		test "show renders the non-custodial editor, prefilled with the seeds until a NIP-65 list is ingested" do
			sign_in

			get settings_relays_url

			assert_response :success
			assert_select "form#relay-form"
			assert_includes response.body, "relay.damus.io" # the seed relays prefill the rows until a list arrives
			assert_select "a[href=?]", settings_profile_path # the shared rail links to the other sections
			assert_includes response.body, "Sign &amp; publish relays"
		end

		test "update enqueues a forced relay-list fetch and accepts" do
			sign_in
			calls = []
			Users::RelayListFetchJob.define_singleton_method(:perform_later) { |*args, **kwargs| calls << [ args, kwargs ] }

			patch settings_relays_url

			assert_response :accepted
			assert_equal [ [ [ @session_pubkey ], { force: true } ] ], calls
		ensure
			Users::RelayListFetchJob.singleton_class.send(:remove_method, :perform_later)
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

		def verify_url = "#{Rails.application.config.x.canonical_origin}/session"
	end
end
