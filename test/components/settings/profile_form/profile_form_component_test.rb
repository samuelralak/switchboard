# frozen_string_literal: true

require "test_helper"

module Settings
	module ProfileForm
		class ProfileFormComponentTest < ViewComponent::TestCase
			def user(**attrs)
				User.new(pubkey: "a" * 64, first_seen_at: Time.current, external_identities: [], **attrs)
			end

			test "prefills the projected columns and wires the publish controller" do
				component = ProfileFormComponent.new(
					user: user(display_name: "Ada Lovelace", name: "ada"),
					pubkey: "a" * 64, publish_relays: [ "wss://relay.example" ]
				)
				render_inline(component)

				assert_selector "form#profile-form[data-controller='profile-form']"
				assert_selector "[data-field='display_name'][value='Ada Lovelace']"
				assert_selector "[data-field='picture']", visible: false # avatar/banner ride in hidden fields now
				assert_selector "[data-field='banner']", visible: false
				assert_text "Sign & publish profile"
			end

			test "carries the existing kind-0 content + tags as the merge base" do
				event = Event.new(content: { "custom" => "keep" }.to_json, tags: [ %w[i github:ada proof] ])
				render_inline(ProfileFormComponent.new(
					user: user, pubkey: "a" * 64, publish_relays: [], metadata_event: event
				))

				base = JSON.parse(page.find("form")["data-profile-form-base-value"])
				assert_includes base["content"], "custom"
				assert_equal [ %w[i github:ada proof] ], base["tags"]
			end

			test "defaults the merge base to empty content for a first profile" do
				render_inline(ProfileFormComponent.new(user: user, pubkey: "a" * 64, publish_relays: []))

				base = JSON.parse(page.find("form")["data-profile-form-base-value"])
				assert_equal "{}", base["content"]
				assert_equal [], base["tags"]
			end
		end
	end
end
