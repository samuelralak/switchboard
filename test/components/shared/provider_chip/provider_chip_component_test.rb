# frozen_string_literal: true

require "test_helper"

module Shared
	module ProviderChip
		class ProviderChipComponentTest < ViewComponent::TestCase
			def test_renders_name_and_truncated_npub
				render_inline(ProviderChipComponent.new(name: "Apollo", npub: "npub1apollo7x9q"))

				assert_selector "span.inline-flex.items-center.gap-2.min-w-0"
				assert_selector "span.font-mono.text-xs.text-ink-muted.truncate"
				assert_text "Apollo · npub1apol…"
			end

			def test_embeds_avatar_without_ring_seeded_by_npub
				render_inline(ProviderChipComponent.new(name: "Apollo", npub: "npub1apollo7x9q"))

				# The chip supplies its own ring wrapper, so the inner avatar has none.
				assert_selector "span.rounded.overflow-hidden.ring-1.ring-border.shrink-0 svg"
				assert_selector "svg[width='20'][height='20']"
			end

			def test_respects_custom_size
				render_inline(ProviderChipComponent.new(name: "Mercury", npub: "npub1mercury42z", size: 32))

				assert_selector "svg[width='32'][height='32']"
			end
		end
	end
end
