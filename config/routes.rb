# frozen_string_literal: true

Rails.application.routes.draw do
	# Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

	# Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
	# Can be used by load balancers and uptime monitors to verify that the app is live.
	get "up" => "rails/health#show", as: :rails_health_check

	# Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
	# get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
	# get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

	# Sign in with Nostr (NIP-98): challenge issues a single-use nonce; create verifies
	# the signed event and establishes the session; destroy signs out.
	resource :session, only: %i[create destroy]
	post "session/challenge", to: "sessions#challenge", as: :session_challenge

	# Stateless NIP-98 API auth for non-browser / nsec clients (per-request Authorization header).
	namespace :api do
		get "identity", to: "identity#show"
	end

	# Defines the root path route ("/")
	root "pages#home"
end
