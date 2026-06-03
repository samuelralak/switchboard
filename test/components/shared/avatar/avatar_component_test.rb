# frozen_string_literal: true

require "test_helper"

module Shared
	module Avatar
		class AvatarComponentTest < ViewComponent::TestCase
			def test_renders_svg_with_default_rounding_and_ring
				render_inline(AvatarComponent.new(seed: "npub1apollo7x9q"))

				assert_selector "span.rounded.overflow-hidden.shrink-0.ring-1.ring-border"
				assert_selector "svg[width='28'][height='28']"
			end

			def test_ring_can_be_disabled
				render_inline(AvatarComponent.new(seed: "npub1apollo7x9q", ring: false))

				assert_selector "span.rounded.overflow-hidden.shrink-0"
				assert_no_selector "span.ring-1"
			end

			def test_large_rounded_variant
				render_inline(AvatarComponent.new(seed: "npub1apollo7x9q", size: 64, rounded: :lg))

				assert_selector "span.rounded-lg"
				assert_selector "svg[width='64'][height='64']"
			end

			def test_deterministic_pattern_for_a_known_seed
				render_inline(AvatarComponent.new(seed: "npub1apollo7x9q"))

				# Same seed must always produce the same number of mirrored cells.
				assert_selector "svg rect", count: 12
			end

			def test_unknown_rounding_falls_back_to_default
				render_inline(AvatarComponent.new(seed: "npub1apollo7x9q", rounded: :nope))

				assert_selector "span.rounded"
				assert_no_selector "span.rounded-lg"
			end
		end
	end
end
