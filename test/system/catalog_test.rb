# frozen_string_literal: true

require "application_system_test_case"

# The catalog list: heterogeneous listings (with/without image or description) render as uniform list
# rows, the fulfillment-mode filter narrows them, and the sort control reorders them client-side.
class CatalogTest < ApplicationSystemTestCase
	NS = Catalog::Listing::CAPABILITY_NAMESPACE

	def setup
		seed(d: "sum", title: "Summarize a thread", desc: "Grounded summaries.", cap: "summarize", price: 120, mode: "automated", ago: 1.hour.ago)
		seed(d: "tr", title: "Translate a document", desc: "Twelve languages.", cap: "translate", price: 500, freq: "hour", mode: "manual", ago: 2.hours.ago)
		seed(d: "rev", title: "Quick code review", desc: "", cap: "review", price: 2000, mode: "manual", ago: 3.hours.ago)
		visit root_path
		assert_text "Summarize a thread"
	end

	test "renders heterogeneous listings as uniform list rows, including a per-hour price" do
		assert_selector '[data-catalog-target="card"]', count: 3
		assert_text "500 sat / hr" # the per-hour listing
		assert_text "Quick code review" # the listing with no description still renders
	end

	test "the fulfillment-mode filter narrows the list" do
		click_button "Automated"

		assert_selector '[data-catalog-target="card"]', text: "Summarize a thread", visible: true
		assert_no_selector '[data-catalog-target="card"]', text: "Translate a document", visible: true
	end

	test "sorting by price reorders the rows" do
		within_sort { click_button "Highest price" }
		assert_equal "Quick code review", first_card_title

		within_sort { click_button "Lowest price" }
		assert_equal "Summarize a thread", first_card_title
	end

	test "the lens switch toggles between services and open requests" do
		seed_request(title: "Fix my bike from a photo", cap: "repair", budget: 5000)
		visit root_path
		assert_text "Summarize a thread"

		assert_selector '[data-catalog-target="card"]', text: "Summarize a thread", visible: true
		assert_no_selector '[data-catalog-target="card"]', text: "Fix my bike from a photo", visible: true

		find('button[data-view="request"]').click # the Open requests lens

		assert_selector '[data-catalog-target="card"]', text: "Fix my bike from a photo", visible: true
		assert_no_selector '[data-catalog-target="card"]', text: "Summarize a thread", visible: true
	end

	private

	def seed_request(title:, cap:, budget:)
		tags = [ [ "d", SecureRandom.hex(4) ], [ "title", title ], [ "t", Requests::OpenRequest.marker ],
						[ "l", cap, NS ], [ "price", budget.to_s, "sat" ] ]
		Event.create!(event_id: SecureRandom.hex(32), pubkey: SecureRandom.hex(32), sig: SecureRandom.hex(64),
									kind: Events::Kinds::CLASSIFIED, content: "Brief.", tags:,
									nostr_created_at: 30.minutes.ago, raw_event: { "id" => SecureRandom.hex(32) })
	end

	def first_card_title
		first('[data-catalog-target="card"]').find("h3").text
	end

	# Open the Sort dropdown, run the block (which clicks an option), letting the popover settle.
	def within_sort
		find("el-dropdown button").click
		yield
	end

	def seed(d:, title:, desc:, cap:, price:, mode:, ago:, freq: nil)
		price_tag = freq ? ["price", price.to_s, "sat", freq] : ["price", price.to_s, "sat"]
		Event.create!(
			event_id: SecureRandom.hex(32), pubkey: SecureRandom.hex(32), sig: SecureRandom.hex(64),
			kind: Events::Kinds::CLASSIFIED, content: desc,
			tags: [ ["d", d], ["title", title], ["t", Catalog::Listing.marker], ["l", cap, NS], price_tag, ["fulfillment", mode] ],
			nostr_created_at: ago, raw_event: { "id" => SecureRandom.hex(32) }
		)
	end
end
