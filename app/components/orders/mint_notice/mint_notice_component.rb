# frozen_string_literal: true

module Orders
	module MintNotice
		# The escrow custodial caveat, shown wherever a buyer commits funds (the order mint picker + the funding
		# step). A Cashu mint holds the backing sats, so a dead or insolvent mint can lose locked funds even
		# though the lock is key-bound, and the timelock refund needs the mint online to pay out. Names the
		# specific mint when one is known (the funding step); generic next to the picker, which lists the mints.
		class MintNoticeComponent < ApplicationComponent
			attr_reader :mint

			def initialize(mint: nil)
				@mint = mint
			end

			# The mint's host reads cleaner than the full URL; fall back to the raw value if it will not parse.
			def host
				URI(mint.to_s).host || mint
			rescue URI::InvalidURIError
				mint
			end
		end
	end
end
