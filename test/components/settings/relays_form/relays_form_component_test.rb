# frozen_string_literal: true

require "test_helper"

module Settings
	module RelaysForm
		class RelaysFormComponentTest < ViewComponent::TestCase
			def user(**attrs)
				User.new(pubkey: "a" * 64, first_seen_at: Time.current, **attrs)
			end

			def write_relay(pubkey, url, read: true, write: true)
				UserRelay.create!(pubkey:, url:, read:, write:, relay_list_event_id: "f" * 64, nostr_created_at: Time.current)
			end

			test "renders the editor form wired to the relay-form controller, with the row template + add field" do
				render_inline(RelaysFormComponent.new(user: user, pubkey: "a" * 64, publish_relays: [ "wss://relay.example" ]))

				assert_selector "form#relay-form[data-controller='relay-form']"
				assert_selector "[data-relay-form-target='newUrl']"
				# The single row markup source the controller clones (read/write toggles + the url field).
				assert_includes rendered_content, "data-relay-form-target=\"rowTemplate\""
				assert_includes rendered_content, "data-field=\"read\""
				assert_includes rendered_content, "data-field=\"write\""
				assert_includes rendered_content, "data-field=\"url\""
				assert_text "Sign & publish relays"
			end

			test "carries the publish relays for the browser broadcast" do
				relays = [ "wss://a.test", "wss://b.test" ]
				render_inline(RelaysFormComponent.new(user: user, pubkey: "a" * 64, publish_relays: relays))

				carried = JSON.parse(page.find("form")["data-relay-form-relays-value"])
				assert_equal relays, carried
			end

			test "prefills the rows from the user's projected NIP-65 relays, with their roles" do
				owner = User.create!(pubkey: SecureRandom.hex(32), first_seen_at: Time.current)
				write_relay(owner.pubkey, "wss://mine.test", read: true, write: false)

				render_inline(RelaysFormComponent.new(user: owner, pubkey: owner.pubkey, publish_relays: []))

				rows = JSON.parse(page.find("form")["data-relay-form-rows-value"])
				assert_equal [ { "url" => "wss://mine.test", "read" => true, "write" => false } ], rows
			end

			test "falls back to the seed relays (read + write) when the user has advertised none" do
				render_inline(RelaysFormComponent.new(user: user, pubkey: "a" * 64, publish_relays: []))

				rows = JSON.parse(page.find("form")["data-relay-form-rows-value"])
				assert_includes rows.pluck("url"), "wss://relay.damus.io"
				assert(rows.all? { |row| row["read"] && row["write"] }, "seed rows default to read + write")
			end
		end
	end
end
