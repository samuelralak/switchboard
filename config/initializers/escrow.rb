# frozen_string_literal: true

# Escrow policy: the vetted mint allowlist and per-order cap, read by Orders::Policy. Non-prod allows the
# local test mint; prod reads ESCROW_MINT_ALLOWLIST.
Rails.application.configure do
	config.x.escrow.max_order_sats = Integer(ENV.fetch("ESCROW_MAX_ORDER_SATS", "100000"))
	config.x.escrow.funding_window_seconds = Integer(ENV.fetch("ESCROW_FUNDING_WINDOW_SECONDS", "3600"))
	config.x.escrow.max_locktime_seconds = Integer(ENV.fetch("ESCROW_MAX_LOCKTIME_SECONDS", "2592000")) # 30 days
	config.x.escrow.default_locktime_seconds = Integer(ENV.fetch("ESCROW_DEFAULT_LOCKTIME_SECONDS", "604800")) # 7 days
	# How far past its locktime a still-settleable order may sit before Escrow::StuckAlert flags it for an
	# operator (the reconcile sweep retries a dead/unresponsive mint forever but never recovers or escalates).
	config.x.escrow.stuck_grace_seconds = Integer(ENV.fetch("ESCROW_STUCK_GRACE_SECONDS", "86400")) # 1 day

	# Tier-2 (arbiter) is opt-in for subjective work: a lower per-order cap, and a minimum locktime lead so a
	# dispute has time to resolve before the consumer's unilateral refund window opens.
	config.x.escrow.tier2_max_order_sats = Integer(ENV.fetch("ESCROW_TIER2_MAX_ORDER_SATS", "25000"))
	config.x.escrow.tier2_min_locktime_seconds = Integer(ENV.fetch("ESCROW_TIER2_MIN_LOCKTIME_SECONDS", "259200")) # 3d

	local_mints = %w[http://127.0.0.1:3338 http://localhost:3338]
	prod_mints = ENV.fetch("ESCROW_MINT_ALLOWLIST", "").split(",").map(&:strip).reject(&:empty?)
	config.x.escrow.mint_allowlist = Rails.env.production? ? prod_mints : local_mints
end
