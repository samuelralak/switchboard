# frozen_string_literal: true

require "test_helper"

module Catalog
	module ServiceDetail
		class ServiceDetailComponentTest < ViewComponent::TestCase
			def test_renders_price_escrow_and_an_order_cta_for_a_whole_sat_listing
				event = hosted_event(title: "Translate", d: "t1", extra_tags: [ %w[price 1500 sat], %w[fulfillment manual] ])

				render_inline(ServiceDetailComponent.new(listing: Catalog::Listing.new(event)))

				assert_text "per request"
				assert_text "escrow on every job"
				assert_selector "form[action='#{url.orders_path}'][method='post']"
				assert_selector "input[name='order[coordinate]'][value='#{Events::Kinds::CLASSIFIED}:#{event.pubkey}:t1']",
					visible: :all
				assert_selector "button", text: /Order this service/
			end

			def test_renders_per_hour_pricing_delivery_window_and_an_honest_escrow_note
				event = hosted_event(title: "Translate", d: "ph",
													extra_tags: [ %w[price 500 sat hour], %w[fulfillment manual], %w[delivery_window 24h] ])

				render_inline(ServiceDetailComponent.new(listing: Catalog::Listing.new(event)))

				assert_text "per hour"        # the price-basis caption, not "per request"
				assert_no_text "per request"
				assert_text "delivers in 24h" # the delivery window is surfaced
				assert_text "agree the hours" # the escrow note avoids a fixed total for a per-hour rate
				assert_no_text "lock 500"
				assert_selector "button", text: /Request this service/ # per-hour is not directly orderable: inert CTA
				assert_no_selector "form[action='#{url.orders_path}']"
			end

			def test_renders_the_markdown_description_as_html
				event = hosted_event(title: "T", d: "t3", content: "## Scope\n\nA **summary** line.")

				render_inline(ServiceDetailComponent.new(listing: Catalog::Listing.new(event)))

				assert_selector ".markdown h2", text: "Scope"
				assert_selector ".markdown strong", text: "summary"
				assert_no_text "## Scope"
			end

			def test_renders_the_input_schema_when_the_listing_declares_one
				schema = [ { label: "Source text", type: "longtext", required: true } ].to_json
				event = hosted_event(title: "T", d: "t2", extra_tags: [ [ "input_schema", schema ] ])

				render_inline(ServiceDetailComponent.new(listing: Catalog::Listing.new(event)))

				assert_text "inputs this service expects"
				assert_text "Source text"
			end

			def test_offers_the_tier_2_escrow_choice_when_the_arbiter_is_configured
				event = hosted_event(title: "T", d: "t2a", extra_tags: [ %w[price 1500 sat] ])

				with_arbiter_key { render_inline(ServiceDetailComponent.new(listing: Catalog::Listing.new(event))) }

				assert_selector "input[name='order[tier]'][value='#{Orders::Tiers::TIER2_ARBITER}']", visible: :all
				assert_text "Mediated escrow"
			end

			def test_hides_the_tier_2_choice_when_the_arbiter_is_unconfigured
				event = hosted_event(title: "T", d: "t2b", extra_tags: [ %w[price 1500 sat] ])

				render_inline(ServiceDetailComponent.new(listing: Catalog::Listing.new(event))) # no arbiter key in ENV

				assert_no_selector "input[name='order[tier]']", visible: :all
				assert_selector "button", text: /Order this service/ # still orderable, tier-1 by default
			end

			def test_lets_the_buyer_pick_the_escrow_mint_and_states_the_custodial_caveat
				event = hosted_event(title: "T", d: "tm", extra_tags: [ %w[price 1500 sat] ])

				render_inline(ServiceDetailComponent.new(listing: Catalog::Listing.new(event)))

				# the test allowlist carries two mints, so the buyer picks rather than a hidden field
				assert_selector "select[name='order[mint_url]']"
				assert_selector "select[name='order[mint_url]'] option[value='http://127.0.0.1:3338']"
				assert_text "can be lost" # the custodial caveat sits under the picker
			end

			# A single-mint allowlist (a realistic prod posture) drops the picker for a hidden field carrying the
			# one vetted mint, and the caveat names it. Exercises the default_mint delegate + the single-mint branch
			# that the two-mint test env never hits, so a broken delegate can't ship green.
			def test_uses_a_hidden_field_naming_the_one_vetted_mint_when_the_allowlist_is_single
				event = hosted_event(title: "T", d: "ts1", extra_tags: [ %w[price 1500 sat] ])

				with_mint_allowlist("https://mint.coinos.io") do
					render_inline(ServiceDetailComponent.new(listing: Catalog::Listing.new(event)))
				end

				assert_no_selector "select[name='order[mint_url]']"
				assert_selector "input[type='hidden'][name='order[mint_url]'][value='https://mint.coinos.io']",
					visible: :all
				assert_text "Escrow mint:" # the MintNotice names the chosen mint
				assert_selector "span.font-mono", text: "mint.coinos.io"
			end

			def test_hides_the_tier_2_choice_above_the_tier_2_cap
				event = hosted_event(title: "T", d: "t2c", extra_tags: [ %w[price 50000 sat] ]) # above the tier-2 cap

				with_arbiter_key { render_inline(ServiceDetailComponent.new(listing: Catalog::Listing.new(event))) }

				assert_no_selector "input[name='order[tier]']", visible: :all
			end

			# A listing posted outside Switchboard (no marker) is not orderable with escrow. Its author sees the
			# republish path to Provider studio, never a dead order form.
			def test_an_externally_posted_listing_shows_the_author_the_republish_path
				event = build_event(title: "External", d: "ext1", extra_tags: [ %w[price 1500 sat] ]) # no marker

				render_inline(ServiceDetailComponent.new(listing: Catalog::Listing.new(event), viewer: viewer(event.pubkey)))

				assert_text "Not published through Switchboard"
				assert_selector "a[href='#{url.new_studio_listing_path}']", text: /Provider studio/
				assert_no_selector "form[action='#{url.orders_path}']"
			end

			# Everyone else sees an honest, disabled action with a reason, never an order it cannot place.
			def test_an_externally_posted_listing_shows_others_a_disabled_request_with_a_notice
				event = build_event(title: "External", d: "ext2", extra_tags: [ %w[price 1500 sat] ]) # no marker

				render_inline(ServiceDetailComponent.new(listing: Catalog::Listing.new(event), viewer: viewer("f" * 64)))

				assert_text "posted outside Switchboard"
				assert_selector "button[disabled]", text: /Request this service/
				assert_no_selector "form[action='#{url.orders_path}']"
				assert_no_selector "a[href='#{url.new_studio_listing_path}']"
			end

			private

			# A catalog event carrying the env-scoped Switchboard service marker, so the listing reads as hosted
			# (orderable here). The marker is what Catalog::Listing#conforms? -- and the order gate -- checks.
			def hosted_event(extra_tags: [], **)
				build_event(extra_tags: extra_tags + [ [ "t", Catalog::Listing.marker ] ], **)
			end

			def viewer(pubkey) = Struct.new(:pubkey).new(pubkey)

			def url = Rails.application.routes.url_helpers
		end
	end
end
