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

	# Opaque NIP-17 inbox cache: anonymous deposit (POST, like a relay accepting an EVENT) +
	# session-authenticated recipient-only fetch (GET, the cookie proves the recipient's pubkey).
	get "inbox", to: "inbox#index"
	post "inbox", to: "inbox#create"

	# Order-scoped messages inbox (NIP-17 DMs); :id selects the open thread.
	get "messages", to: "messages#index", as: :messages
	get "messages/:id", to: "messages#index", as: :message

	# Generic keyless-browser NIP-17 DM client (#32 proof): session-authenticated; the browser does all
	# crypto + relay I/O. Distinct from the order-scoped messages#index above.
	get "dms", to: "direct_messages#index", as: :direct_messages

	# Account settings (relays, profile, signer); reached from the sidebar + the avatar menu.
	get "settings", to: "settings#show", as: :settings

	# Provider studio: author + publish your own kind-30402 service listings. Session-authenticated.
	# The listing is signed + broadcast IN THE BROWSER with the provider's key (non-custodial, §6.3),
	# so there is no create POST: index lists, new authors, preview re-renders the on-demand buyer view.
	get "studio", to: "studio#index", as: :studio
	get "studio/new", to: "studio#new", as: :new_studio_listing
	post "studio/preview", to: "studio#preview", as: :studio_preview
	# Edit re-publishes under the same d-tag (supersede). Keyed on the stable d-tag (?d=) rather than the
	# DB row id, which is regenerated when a re-publish supersedes the coordinate.
	get "studio/edit", to: "studio#edit", as: :edit_studio_listing

	# Defines the root path route ("/")
	root "pages#home"
end
