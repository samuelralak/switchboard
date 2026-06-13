# frozen_string_literal: true

require "test_helper"

module Profiles
	module Header
		class HeaderComponentTest < ViewComponent::TestCase
			def user(**attrs)
				User.new(pubkey: "a" * 64, first_seen_at: Time.current, external_identities: [], **attrs)
			end

			test "renders the display name, npub, and a verified nip05" do
				verified = user(display_name: "Apollo", nip05: "apollo@x.com", nip05_verified: true)
				render_inline(HeaderComponent.new(user: verified))

				assert_selector "h1", text: "Apollo"
				assert_text "apollo@x.com"
				assert_selector "i.hgi-checkmark-badge-01" # the verified check
				assert_text "npub1" # the npub, mono
			end

			test "shows the verification check only when nip05 is verified" do
				render_inline(HeaderComponent.new(user: user(display_name: "X", nip05: "x@y.com", nip05_verified: false)))

				assert_text "x@y.com"
				assert_no_selector "i.hgi-checkmark-badge-01"
			end

			test "falls back to an identicon when there is no picture, and uses the picture when present" do
				render_inline(HeaderComponent.new(user: user(display_name: "X")))
				assert_selector "svg" # identicon

				render_inline(HeaderComponent.new(user: user(display_name: "X", picture: "https://h/a.png")))
				assert_selector "img[src='https://h/a.png']"
			end

			test "links only an http(s) website, stripped of its scheme" do
				render_inline(HeaderComponent.new(user: user(display_name: "X", website: "https://apollo.dev/")))

				assert_selector "a[href='https://apollo.dev/']", text: "apollo.dev"
			end

			test "drops a non-http website (anti-xss)" do
				render_inline(HeaderComponent.new(user: user(display_name: "X", website: "javascript:alert(1)")))

				assert_no_selector "a[href^='javascript']"
			end

			test "renders the bio as sanitized markdown" do
				render_inline(HeaderComponent.new(user: user(display_name: "X", about: "## Hi\n\nI **build** things.")))

				assert_selector ".markdown h2", text: "Hi"
				assert_selector ".markdown strong", text: "build"
			end
		end
	end
end
