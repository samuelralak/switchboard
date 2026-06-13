# frozen_string_literal: true

require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
	def npub_for(hex) = Nostr::Bech32.npub_encode(hex)

	def listing_event(pubkey:, d_tag:, title:, status: nil)
		tags = [ [ "d", d_tag ], [ "title", title ], [ "t", Catalog::Listing.marker ], %w[price 2000 sat] ]
		tags << [ "status", status ] if status

		Event.create!(
			event_id: SecureRandom.hex(32), pubkey:, sig: SecureRandom.hex(64), kind: Events::Kinds::CLASSIFIED,
			content: title, nostr_created_at: Time.current, raw_event: { "id" => SecureRandom.hex(32) },
			tags:
		)
	end

	def request_event(pubkey:, d_tag:, title:, status: nil)
		tags = [ [ "d", d_tag ], [ "title", title ], [ "t", Requests::OpenRequest.marker ], %w[price 5000 sat] ]
		tags << [ "status", status ] if status

		Event.create!(
			event_id: SecureRandom.hex(32), pubkey:, sig: SecureRandom.hex(64), kind: Events::Kinds::CLASSIFIED,
			content: title, nostr_created_at: Time.current, raw_event: { "id" => SecureRandom.hex(32) },
			tags:
		)
	end

	# Establishes a real NIP-98 session (also projects the bare User row, via Users::FindOrCreate at sign-in),
	# so the viewer == the profile's pubkey and the owner manage branch renders. Sets @session_pubkey.
	def sign_in
		keypair = Nostr::Keygen.new.generate_key_pair
		@session_pubkey = keypair.public_key.to_s
		tags = nip98_tags(url: verify_url, challenge: LoginChallenge.issue.nonce)
		event = sign_event(kind: Events::Kinds::HTTP_AUTH, tags:, keypair:)
		post session_url, headers: { "Authorization" => "Nostr #{Base64.strict_encode64(JSON.generate(event))}" }
		assert_response :created
	end

	def verify_url = "#{Rails.application.config.x.canonical_origin}/session"

	test "renders a known provider's identity from their kind-0 projection" do
		user = User.create!(pubkey: SecureRandom.hex(32), first_seen_at: Time.current,
			display_name: "Apollo", name: "apollo", nip05: "apollo@example.com")

		get profile_url(npub: npub_for(user.pubkey))

		assert_response :success
		assert_select "h1", text: "Apollo"
		assert_includes response.body, "apollo@example.com"
		assert_includes response.body, user.npub.truncate(24, omission: "…") # the npub (mono)
	end

	test "shows only a provider's live services to visitors (drafts stay private), as cards with drawers" do
		user = User.create!(pubkey: SecureRandom.hex(32), first_seen_at: Time.current, display_name: "Apollo")
		listing_event(pubkey: user.pubkey, d_tag: "logo", title: "Logo design") # active (no status tag)
		listing_event(pubkey: user.pubkey, d_tag: "wip", title: "Hidden draft", status: "inactive") # unpublished

		get profile_url(npub: npub_for(user.pubkey))

		assert_response :success
		assert_includes response.body, "Logo design"
		assert_not_includes response.body, "Hidden draft" # a visitor never sees an unpublished listing or its count
		assert_select "##{Catalog::Ui::State::DRAWER_TARGET}" # the order-drawer mount
	end

	test "the owner manages both their services and requests in place, not as order cards" do
		sign_in
		listing_event(pubkey: @session_pubkey, d_tag: "logo", title: "Logo design") # active
		listing_event(pubkey: @session_pubkey, d_tag: "draft", title: "Draft service", status: "inactive")
		request_event(pubkey: @session_pubkey, d_tag: "need", title: "Need a logo") # open

		get profile_url(npub: npub_for(@session_pubkey))

		assert_response :success
		assert_select "[data-controller=?]", "my-listings" # the services manage wrapper
		assert_select "[data-controller=?]", "my-requests" # the requests manage wrapper
		assert_select "a[href=?]", settings_profile_path # owner identity action: edit profile
		assert_includes response.body, "Publish a service" # services heading: ghost create
		assert_includes response.body, "Post a request" # requests heading: ghost create
		assert_includes response.body, "Logo design"
		assert_includes response.body, "Draft service" # inactive is the owner's to see, not the public's
		assert_includes response.body, "Need a logo" # the posted request, managed in place
		assert_select "button[data-action=?]", "my-listings#toggleStatus", count: 2 # Unpublish/Re-publish per listing
		assert_select "button[data-action=?]", "my-requests#toggleStatus", count: 1 # Withdraw/Re-post per request
		assert_select "##{Catalog::Ui::State::DRAWER_TARGET}", count: 0 # manage rows aren't orderable: no drawer mount
	end

	test "shows the provider's open requests as cards that mount their drawers" do
		user = User.create!(pubkey: SecureRandom.hex(32), first_seen_at: Time.current, display_name: "Apollo")
		request_event(pubkey: user.pubkey, d_tag: "logo-need", title: "Need a logo") # open (no status tag)

		get profile_url(npub: npub_for(user.pubkey))

		assert_response :success
		assert_includes response.body, "Need a logo"
		assert_select "##{Requests::Ui::State::DRAWER_TARGET}" # the request-drawer mount
		assert_includes response.body, "offering anything right now" # visitor services-empty (a request, no service)
	end

	test "shows one unified empty state when the provider has neither services nor requests" do
		user = User.create!(pubkey: SecureRandom.hex(32), first_seen_at: Time.current, display_name: "Apollo")

		get profile_url(npub: npub_for(user.pubkey))

		assert_response :success
		assert_includes response.body, "Nothing here yet"
		assert_select "h2", text: /Services/, count: 0 # both-empty suppresses the two section headings
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
		# Enqueued WITHOUT force: an anonymous, refresh-on-every-load read path must respect the job's per-pubkey
		# cooldown, so repeated hits on an unprojected npub do not re-fetch from the relays each time.
		assert_equal [ [ [ hex ], {} ] ], calls
	ensure
		Users::MetadataFetchJob.singleton_class.send(:remove_method, :perform_later)
	end

	test "an owner with no services or requests gets the unified empty state with both create CTAs" do
		sign_in

		get profile_url(npub: npub_for(@session_pubkey))

		assert_response :success
		assert_includes response.body, "Your marketplace presence is empty"
		assert_select "a[href=?]", new_request_path # the post-request CTA (no navbar fallback for requests)
		assert_includes response.body, "Publish a service" # the ghost publish-service CTA
		assert_select "h2", text: /Services/, count: 0 # both sections are suppressed in the unified state
	end
end
