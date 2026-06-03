# frozen_string_literal: true

require "test_helper"

module Shared
	module Eyebrow
		class EyebrowComponentTest < ViewComponent::TestCase
			def test_renders_content_with_base_classes
				render_inline(EyebrowComponent.new.with_content("reference service"))

				assert_selector "p.font-mono.text-xs.uppercase.tracking-widest.text-copper"
				assert_text "reference service"
			end

			def test_applies_optional_margin
				render_inline(EyebrowComponent.new(margin: "mb-2.5").with_content("how it works"))

				assert_selector "p.text-copper.mb-2\\.5"
				assert_text "how it works"
			end

			def test_omits_margin_when_blank
				render_inline(EyebrowComponent.new.with_content("escrow"))

				assert_no_selector "p[class$=' ']"
				assert_text "escrow"
			end
		end
	end
end
