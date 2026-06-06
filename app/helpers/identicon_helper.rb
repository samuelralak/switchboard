# frozen_string_literal: true

# A deterministic geometric identicon derived from a Nostr pubkey: a 5x5 left-right symmetric grid
# (GitHub-style), with cells and hue taken from the pubkey's own bytes. Used as the avatar fallback when
# an identity has no kind-0 picture, so every pubkey gets a distinct, stable mark on the dark theme. The
# SVG is base64-encoded into a data: URI and rendered with image_tag, so there is no raw HTML to mark
# html_safe and no injection surface (CSP allows data: images).
module IdenticonHelper
	# An <img> identicon for a pubkey, or "" if the pubkey is malformed.
	def identicon_tag(pubkey, size: 28, html_class: nil)
		bytes = pubkey.to_s.scan(/../).map { |pair| pair.to_i(16) }
		return "" if bytes.length < 16

		image_tag(identicon_data_uri(bytes), alt: "", width: size, height: size, class: html_class)
	end

	private

	def identicon_data_uri(bytes)
		fill = "hsl(#{bytes[0] * 360 / 256}, 50%, 60%)"
		attrs = %(xmlns="http://www.w3.org/2000/svg" viewBox="0 0 5 5" fill="#{fill}" shape-rendering="crispEdges")
		svg = "<svg #{attrs}>#{identicon_cells(bytes)}</svg>"
		"data:image/svg+xml;base64,#{Base64.strict_encode64(svg)}"
	end

	# 15 source cells (5 rows x 3 columns) mirrored into a symmetric 5-wide grid; a cell is on when its
	# pubkey byte is even.
	def identicon_cells(bytes)
		(0...5).flat_map do |row|
			(0...3).filter_map do |col|
				next unless bytes[(row * 3) + col + 1].even?

				[ col, 4 - col ].uniq.map { |x| %(<rect x="#{x}" y="#{row}" width="1" height="1"/>) }.join
			end
		end.join
	end
end
