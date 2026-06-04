# frozen_string_literal: true

module Messages
	# A counterparty's signed history, surfaced so a provider can judge an incoming request:
	# completed orders as a consumer, sats settled (proof-of-payment), account age, and any
	# release disputes (the provider's residual risk, brief §10 "honest asymmetry"). A
	# placeholder shape; derived from raw npub history once messaging is wired.
	TrackRecord = Data.define(:completed, :settled, :since, :disputes, :fresh) do
		def fresh? = fresh
		def flagged? = disputes.positive?
	end
end
