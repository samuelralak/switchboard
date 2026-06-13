# frozen_string_literal: true

require "test_helper"

module Orders
	module MintNotice
		class MintNoticeComponentTest < ViewComponent::TestCase
			def test_states_the_custodial_caveat_without_naming_a_mint
				render_inline(MintNoticeComponent.new)

				assert_text "afford to lose"
				assert_no_text "Escrow mint:"
			end

			def test_names_the_mint_host_in_mono_when_given
				render_inline(MintNoticeComponent.new(mint: "https://mint.coinos.io"))

				assert_text "Escrow mint:"
				assert_selector "span.font-mono", text: "mint.coinos.io"
				assert_text "afford to lose"
			end

			def test_falls_back_to_the_raw_value_when_it_is_not_a_url
				render_inline(MintNoticeComponent.new(mint: "coinos"))

				assert_selector "span.font-mono", text: "coinos"
			end
		end
	end
end
