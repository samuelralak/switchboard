# frozen_string_literal: true

module Shared
	module Avatar
		# Renders a deterministic 5x5 mirrored identicon SVG from a seed string.
		class AvatarComponent < ApplicationComponent
			ROUNDINGS = { default: "rounded", lg: "rounded-lg" }.freeze

			def initialize(seed:, size: 28, rounded: :default, ring: true)
				@seed = seed.to_s
				@size = size
				@rounded = ROUNDINGS.key?(rounded.to_s.to_sym) ? rounded.to_s.to_sym : :default
				@ring = ring
			end

			def wrapper_class
				base = "#{ROUNDINGS.fetch(@rounded)} overflow-hidden shrink-0"
				@ring ? "#{base} ring-1 ring-border" : base
			end

			def identicon
				helpers = ActionController::Base.helpers
				h = hash_str(@seed)
				hue = h % 360
				helpers.tag.svg(
					helpers.safe_join(rects(helpers, h, hue)),
					viewBox: "0 0 5 5", width: @size, height: @size,
					"shape-rendering": "crispEdges", style: "background:#{background(hue)}"
				)
			end

			private

			def hash_str(string)
				hash = 2_166_136_261
				string.each_char do |char|
					hash ^= char.ord
					hash = (hash * 16_777_619) & 0xFFFFFFFF
				end
				hash
			end

			def rects(helpers, hash, hue)
				cells = []
				(0..4).each do |y|
					color = "oklch(0.72 0.1 #{(hue + (y * 9)) % 360})"
					(0..2).each do |x|
						next unless (hash >> ((y * 3) + x)).allbits?(1)

						cells.concat(cell_pair(helpers, x, y, color))
					end
				end
				cells
			end

			def cell_pair(helpers, pos_x, pos_y, color)
				pair = [ helpers.tag.rect(x: pos_x, y: pos_y, width: 1, height: 1, fill: color) ]
				pair << helpers.tag.rect(x: 4 - pos_x, y: pos_y, width: 1, height: 1, fill: color) if pos_x < 2
				pair
			end

			def background(hue) = "oklch(0.24 0.02 #{(hue + 200) % 360})"
		end
	end
end
