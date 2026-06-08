# frozen_string_literal: true

module Orders
	# The vetted mint allowlist and per-order cap, from config/initializers/escrow.rb.
	module Policy
		module_function

		def max_order_sats = Rails.application.config.x.escrow.max_order_sats
		def funding_window = Rails.application.config.x.escrow.funding_window_seconds.seconds
		def max_locktime = Rails.application.config.x.escrow.max_locktime_seconds.seconds
		def default_locktime_seconds = Rails.application.config.x.escrow.default_locktime_seconds
		def mint_allowlist = Array(Rails.application.config.x.escrow.mint_allowlist)
		def mint_allowed?(url) = mint_allowlist.include?(url)
	end
end
