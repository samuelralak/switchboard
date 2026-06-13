# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += %i[
	passw email secret token _key crypt salt certificate otp ssn cvv cvc
]

# Escrow lock data: public values, but kept out of logs/Sentry for correlation hygiene (the spendable
# proof secret and any private key never reach the server). `proofs` covers the nested proof Y values
# and amounts; the *_pubkey keys are distinct from the bare `pubkey` used elsewhere, so login/profile
# pubkeys stay visible for debugging.
Rails.application.config.filter_parameters += %i[
	hashlock lock_pubkey refund_pubkey arbiter_pubkey proofs preimage witness
]
