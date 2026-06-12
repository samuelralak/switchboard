# frozen_string_literal: true

require "test_helper"

module Catalog
	module ServiceDetail
		class ServiceDetailComponentTest < ViewComponent::TestCase
			def test_renders_price_escrow_and_an_order_cta_for_a_whole_sat_listing
				event = build_event(title: "Translate", d: "t1", extra_tags: [ %w[price 1500 sat], %w[fulfillment manual] ])

				render_inline(ServiceDetailComponent.new(listing: Catalog::Listing.new(event)))

				assert_text "per request"
				assert_text "escrow on every job"
				assert_selector "form[action='#{Rails.application.routes.url_helpers.orders_path}'][method='post']"
				assert_selector "input[name='order[coordinate]'][value='#{Events::Kinds::CLASSIFIED}:#{event.pubkey}:t1']",
					visible: :all
				assert_selector "button", text: /Order this service/
			end

			def test_renders_per_hour_pricing_delivery_window_and_an_honest_escrow_note
				event = build_event(title: "Translate", d: "ph",
													extra_tags: [ %w[price 500 sat hour], %w[fulfillment manual], %w[delivery_window 24h] ])

				render_inline(ServiceDetailComponent.new(listing: Catalog::Listing.new(event)))

				assert_text "per hour"        # the price-basis caption, not "per request"
				assert_no_text "per request"
				assert_text "delivers in 24h" # the delivery window is surfaced
				assert_text "agree the hours" # the escrow note avoids a fixed total for a per-hour rate
				assert_no_text "lock 500"
				assert_selector "button", text: /Request this service/ # per-hour is not directly orderable: inert CTA
				assert_no_selector "form[action='#{Rails.application.routes.url_helpers.orders_path}']"
			end

			def test_renders_the_markdown_description_as_html
				event = build_event(title: "T", d: "t3", content: "## Scope\n\nA **summary** line.")

				render_inline(ServiceDetailComponent.new(listing: Catalog::Listing.new(event)))

				assert_selector ".markdown h2", text: "Scope"
				assert_selector ".markdown strong", text: "summary"
				assert_no_text "## Scope"
			end

			def test_renders_the_input_schema_when_the_listing_declares_one
				schema = [ { label: "Source text", type: "longtext", required: true } ].to_json
				event = build_event(title: "T", d: "t2", extra_tags: [ [ "input_schema", schema ] ])

				render_inline(ServiceDetailComponent.new(listing: Catalog::Listing.new(event)))

				assert_text "inputs this service expects"
				assert_text "Source text"
			end

			def test_offers_the_tier_2_escrow_choice_when_the_arbiter_is_configured
				event = build_event(title: "T", d: "t2a", extra_tags: [ %w[price 1500 sat] ])

				with_arbiter_key { render_inline(ServiceDetailComponent.new(listing: Catalog::Listing.new(event))) }

				assert_selector "input[name='order[tier]'][value='#{Orders::Tiers::TIER2_ARBITER}']", visible: :all
				assert_text "Mediated escrow"
			end

			def test_hides_the_tier_2_choice_when_the_arbiter_is_unconfigured
				event = build_event(title: "T", d: "t2b", extra_tags: [ %w[price 1500 sat] ])

				render_inline(ServiceDetailComponent.new(listing: Catalog::Listing.new(event))) # no arbiter key in ENV

				assert_no_selector "input[name='order[tier]']", visible: :all
				assert_selector "button", text: /Order this service/ # still orderable, tier-1 by default
			end

			def test_hides_the_tier_2_choice_above_the_tier_2_cap
				event = build_event(title: "T", d: "t2c", extra_tags: [ %w[price 50000 sat] ]) # > 25k tier-2 cap, < 100k tier-1

				with_arbiter_key { render_inline(ServiceDetailComponent.new(listing: Catalog::Listing.new(event))) }

				assert_no_selector "input[name='order[tier]']", visible: :all
			end
		end
	end
end
