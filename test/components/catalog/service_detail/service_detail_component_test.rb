# frozen_string_literal: true

require "test_helper"

module Catalog
	module ServiceDetail
		class ServiceDetailComponentTest < ViewComponent::TestCase
			def test_renders_price_escrow_and_the_request_cta
				event = build_event(title: "Translate", d: "t1", extra_tags: [ %w[price 1500 sat], %w[fulfillment manual] ])

				render_inline(ServiceDetailComponent.new(listing: Catalog::Listing.new(event)))

				assert_text "per request"
				assert_text "escrow · every job"
				assert_selector "button", text: /Request this service/
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
		end
	end
end
