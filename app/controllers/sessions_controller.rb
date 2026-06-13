# frozen_string_literal: true

class SessionsController < ApplicationController
	include Nip98Authentication

	# These two endpoints are authenticated by the signed NIP-98 event plus a single-use
	# server nonce, not by an ambient session cookie (the user has no session yet at
	# sign-in), so Rails' cookie CSRF token is neither available nor meaningful. A
	# cross-site attacker cannot forge a Schnorr signature over a fresh nonce. CSRF stays
	# on everywhere else, including #destroy.
	skip_forgery_protection only: %i[challenge create]

	rate_limit to: 10, within: 1.minute, only: :challenge, by: -> { client_ip }

	# POST /session/challenge -> issue a single-use nonce for the client to sign.
	def challenge
		login_challenge = LoginChallenge.issue
		render json: { challenge: login_challenge.nonce, expires_at: login_challenge.expires_at.to_i }
	end

	# POST /session -> verify the NIP-98 event in the Authorization header, establish the session.
	def create
		event = decode_nip98_event(request.headers["Authorization"])
		user = Sessions::Authenticate.call(event_data: event, http_method: request.request_method, url: verify_url)

		start_new_session_for(user)
		head :created
	rescue AuthenticationError, InvalidEventError
		head :unauthorized # do not disclose which gate failed
	end

	# DELETE /session -> sign out (CSRF-protected; the user has a session here).
	def destroy
		terminate_session
		redirect_to root_path, status: :see_other
	end

	private

	# The `u` tag is checked against a config-derived URL, never request.url/Host (which a
	# proxy could spoof); the client signs exactly this string.
	def verify_url = "#{Rails.application.config.x.canonical_origin}#{session_path}"
end
