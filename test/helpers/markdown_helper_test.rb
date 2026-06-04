# frozen_string_literal: true

require "test_helper"

class MarkdownHelperTest < ActionView::TestCase
	test "renders GFM markdown to safe HTML" do
		html = markdown("## Scope\n\nDelivers a **report** with a [link](https://example.com).")

		assert_includes html, "<h2>"
		assert_includes html, "<strong>report</strong>"
		assert_includes html, %(href="https://example.com")
		assert_predicate html, :html_safe?
	end

	test "escapes raw HTML instead of executing it" do
		html = markdown("Hello <script>alert(1)</script> world")

		assert_not_includes html, "<script>"
		assert_includes html, "&lt;script&gt;"
	end

	test "drops dangerous link schemes such as javascript" do
		assert_not_includes markdown("[tap](javascript:alert(1))"), "javascript:"
	end

	test "blank input renders nothing" do
		assert_equal "", markdown(nil)
		assert_equal "", markdown("   ")
	end

	test "markdown_to_text strips formatting and decodes entities for teasers" do
		text = markdown_to_text("# Pitch & promise\n\n- **fast**\n- cheap")

		assert_equal "Pitch & promise fast cheap", text
	end
end
