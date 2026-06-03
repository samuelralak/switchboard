# frozen_string_literal: true

require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
	test "renders the home page at root" do
		get root_url
		assert_response :success
	end

	test "renders an ingested listing in the catalog grid" do
		build_event(title: "Logo design", d: "logo")

		get root_url

		assert_response :success
		assert_select "#catalog_listings"
		assert_includes response.body, "Logo design"
	end

	test "applies the search query" do
		build_event(title: "Logo design", d: "logo")
		build_event(title: "Tax filing", d: "tax")

		get root_url, params: { q: "logo" }

		assert_response :success
		assert_includes response.body, "Logo design"
		assert_not_includes response.body, "Tax filing"
	end

	test "tolerates a non-hash search param without erroring" do
		get root_url, params: { search: "foo" }
		assert_response :success

		get root_url, params: { search: [ "a" ] }
		assert_response :success
	end
end
