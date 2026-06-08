# frozen_string_literal: true

require "test_helper"

module Shared
	module AuthoringPage
		class AuthoringPageComponentTest < ViewComponent::TestCase
			def component
				AuthoringPageComponent.new(
					stimulus: "request-form",
					values: { "pubkey" => "abc", "marker" => "switchboard-request-test", "relays" => [ "wss://r" ].to_json },
					sections: [
						{ id: "details", title: "Details", required: true },
						{ id: "budget", title: "Budget", required: false }
					],
					heading: "Post a request", subtitle: "Describe it"
				)
			end

			test "renders the stimulus wrapper, the value attributes, the rail, and every slot" do
				render_inline(component) do |page|
					page.with_form { '<div id="the-form">the form</div>'.html_safe }
					page.with_actions { '<button type="button">Publish</button>'.html_safe }
					page.with_receipt { '<div id="the-receipt">done</div>'.html_safe }
					page.with_preview { '<div id="the-preview">the preview</div>'.html_safe }
				end

				assert_selector "[data-controller='request-form']"
				assert_selector "[data-request-form-pubkey-value='abc']"
				assert_selector "[data-request-form-target='composer']"
				assert_selector "[data-request-form-target='navItem']", count: 2
				assert_selector "[data-request-form-target='navItem'][data-action='request-form#navClick']", count: 2
				assert_selector "#the-form"
				assert_selector "#the-receipt"
				assert_selector "#the-preview"
				assert_text "Post a request"
			end
		end
	end
end
