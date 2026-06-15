# frozen_string_literal: true

# Interim attestation trigger. After a browser publish (a service from the studio or an open request from the
# request form), the client reports the signed kind-30402 here so the platform can attest it. Session-
# authenticated (the same standard as the studio/requests flows, not the NIP-98 /api standard). Best-effort:
# verification + issuance live in Attestation::Attest; a bad/forged event is a 4xx, never a 500, and never
# affects the already-completed publish.
class AttestationsController < ApplicationController
	before_action :require_login

	def create
		Attestation::Attest.call(event_data: reported_event, reporter_pubkey: current_user.pubkey)
		head :ok
	rescue InvalidEventError, ActionController::ParameterMissing
		head :unprocessable_content
	end

	private

	def reported_event
		params.require(:event).to_unsafe_h
	end
end
