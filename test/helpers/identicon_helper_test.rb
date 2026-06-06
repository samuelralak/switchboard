# frozen_string_literal: true

require "test_helper"

class IdenticonHelperTest < ActionView::TestCase
	test "renders a deterministic data-uri img for a pubkey" do
		html = identicon_tag("a" * 64, size: 24)

		assert_match %r{<img[^>]+src="data:image/svg\+xml;base64,}, html
		assert_includes html, %(width="24")
		assert_equal html, identicon_tag("a" * 64, size: 24), "same pubkey yields the same identicon"
		assert_not_equal html, identicon_tag("b" * 64, size: 24), "different pubkeys differ"
	end

	test "returns blank for a malformed pubkey" do
		assert_equal "", identicon_tag("nope")
	end
end
