# frozen_string_literal: true

require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
	test "renders the provider queue with the request, service, and client context" do
		get messages_url

		assert_response :success
		assert_select "a[href=?]", message_path("0x4a90b2")     # an incoming request links to its thread
		assert_select "h2", text: /Code review a snippet/       # the first request opens in the detail
		assert_select "p", text: /request from bob/i            # the filled schema the client sent
		assert_select "dt", text: /Language/                    # a schema field label
		assert_select "button", text: /Accept request/          # the provider decision for a new request
		assert_match(/no track record yet/, response.body)      # a fresh client's signed history
		# the service title opens a slide-over drawer holding the full listing detail
		assert_select "button[commandfor=?]", "service-drawer"
		assert_select "dialog#service-drawer"
		assert_match(/inputs this service expects/, response.body)
		assert_match(/kind 30402/, response.body)               # the service-listing conformance line
	end

	test "opens a settled request and shows the provider's delivery" do
		get message_url("0x22f7d1")

		assert_response :success
		assert_select "h2", text: /Translate EN/
		assert_select "p", text: /your delivery/i
		assert_match(/58 completed/, response.body)             # the client's track record
	end
end
