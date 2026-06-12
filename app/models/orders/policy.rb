# frozen_string_literal: true

module Orders
	# Reads escrow policy from config/initializers/escrow.rb: the vetted mint allowlist, the per-order caps, and
	# the locktime bounds. Tier-2 (arbiter) is opt-in for subjective work, so it carries its own lower cap and a
	# minimum locktime lead -- a dispute needs time to resolve before the consumer's refund window opens.
	module Policy
		class << self
			# Raw values read straight from config. default_locktime_seconds is a plain Integer handed to the
			# browser; the caps are sats.
			delegate :max_order_sats, :tier2_max_order_sats, :default_locktime_seconds, to: :config

			# The per-order sat cap for a tier (Tier-2 is lower). One rule, shared by CreateContract + the model.
			def cap_for(tier)
				tier == Orders::Tiers::TIER2_ARBITER ? tier2_max_order_sats : max_order_sats
			end

			def funding_window
				config.funding_window_seconds.seconds
			end

			def max_locktime
				config.max_locktime_seconds.seconds
			end

			def tier2_min_locktime
				config.tier2_min_locktime_seconds.seconds
			end

			def mint_allowlist
				Array(config.mint_allowlist)
			end

			def mint_allowed?(url)
				mint_allowlist.include?(url)
			end

			# The mint pre-filled into a new order / claim (nil when none is vetted -> the action stays inert).
			def default_mint
				mint_allowlist.first
			end

			private

			def config
				Rails.application.config.x.escrow
			end
		end
	end
end
