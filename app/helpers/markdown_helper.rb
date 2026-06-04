# frozen_string_literal: true

# Renders NIP-99 listing content (Markdown, brief §7.1) to HTML for the service
# drawers. Listing content is untrusted Nostr data, so it passes through two
# layers: Commonmarker escapes raw HTML by default (unsafe: false) and never emits
# dangerous links, then Rails' sanitize() applies its vetted allowlist (which also
# drops form controls and unknown tags). The CSP is the last line of defense.
module MarkdownHelper
	# Safe HTML, meant to be rendered inside a `.markdown` container.
	def markdown(text)
		return "".html_safe if text.blank?

		sanitize(Commonmarker.to_html(text.to_s, options: { render: { escape: true } }))
	end

	# Plain-text projection of the same content, for card teasers / clamped blurbs.
	def markdown_to_text(text)
		return "" if text.blank?

		CGI.unescapeHTML(strip_tags(markdown(text))).squish
	end
end
