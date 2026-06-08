# frozen_string_literal: true

module Cashu
	# One NUT-07 proof state from a mint: the proof's Y, its state ("SPENT"/"UNSPENT"), and the spend witness
	# (the HTLC preimage is revealed here on a spent proof). A value object, observe-only; produced by
	# Cashu::Checkstate and consumed by the order settlement/funding/reconcile services.
	ProofState = Data.define(:y, :state, :witness) do
		def spent? = state == "SPENT"
		def unspent? = state == "UNSPENT"
	end
end
