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
		# The winning party of a ruled Tier-2 dispute fetches the arbiter's signatures to finish the 2-of-3
		# spend; data endpoint (JSON), kept off the Turbo OrdersController.
		post "orders/:order_id/arbiter_signatures", to: "arbiter_signatures#create", as: :order_arbiter_signatures
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

	# In-app notifications: the full feed (index), per-notification mark-as-read (update), and a seen-marker
	# the bell posts when its dropdown opens.
	resources :notifications, only: %i[index update] do
		post :seen, on: :collection
	end

	# Account settings: a section rail of sub-pages (Profile / Relays / ...), reached from the sidebar + the
	# avatar menu. /settings lands on the default sub-page.
	get "settings", to: "settings#show", as: :settings
	namespace :settings do
		# Non-custodial profile editor: show renders the form; update is the post-broadcast reconcile (the browser
		# signs + broadcasts the kind-0 itself, then PATCHes here to force-fetch it back). settings_profile_path.
		# controller: keeps the singular ProfileController name (a singular resource defaults to the plural).
		resource :profile, only: %i[show update], controller: "profile"
		# Non-custodial relay-list (NIP-65) editor: show renders the form; update is the post-broadcast reconcile
		# (the browser signs + broadcasts the kind-10002, then PATCHes here to force-fetch it back).
		resource :relays, only: %i[show update]
	end

	# Open requests (funded bounties): the public board (index), and authoring your own (new + preview).
	# Like the studio, posting is signed + broadcast IN THE BROWSER with the consumer's key (non-custodial,
	# §6.3), so there is no create POST: new authors, preview re-renders the on-demand request view.
	get "requests", to: "requests#index", as: :requests
	get "requests/new", to: "requests#new", as: :new_request
	post "requests/preview", to: "requests#preview", as: :request_preview
	# Edit re-posts under the same d-tag (supersede). Keyed on the stable d-tag (?d=) rather than the DB
	# row id, which is regenerated when a re-post supersedes the coordinate.
	get "requests/edit", to: "requests#edit", as: :edit_request

	# Provider studio: author + publish your own kind-30402 service listings. Session-authenticated.
	# The listing is signed + broadcast IN THE BROWSER with the provider's key (non-custodial, §6.3),
	# so there is no create POST: index lists, new authors, preview re-renders the on-demand buyer view.
	get "studio", to: "studio#index", as: :studio
	get "studio/new", to: "studio#new", as: :new_studio_listing
	post "studio/preview", to: "studio#preview", as: :studio_preview
	# Edit re-publishes under the same d-tag (supersede). Keyed on the stable d-tag (?d=) rather than the
	# DB row id, which is regenerated when a re-publish supersedes the coordinate.
	get "studio/edit", to: "studio#edit", as: :edit_studio_listing

	# A provider's public profile = their portfolio: identity (kind-0) + their published services. Public; the
	# owner additionally gets manage controls. npub-keyed so it is shareable. A valid-but-unindexed npub lazily
	# fetches its kind-0 and shows a placeholder rather than 404ing (the pubkey is real even if not yet ingested).
	get "u/:npub", to: "profiles#show", as: :profile

	# Escrow orders (session-authed): place an order from a listing/request coordinate, and report the HTLC
	# funding lock. The browser does the Cashu locking/keys; Rails records only observable lock data.
	resources :orders, only: %i[create show index]
	post "orders/:id/funding", to: "orders#fund", as: :order_funding
	post "orders/:id/delivery", to: "orders#deliver", as: :order_delivery # provider records the delivery assertion
	post "orders/:id/release", to: "orders#release", as: :order_release # consumer records the release assertion
	post "orders/:id/settle", to: "orders#settle", as: :settle_order # re-derive state from the mint after a spend
	post "orders/:id/dispute", to: "orders#dispute", as: :order_dispute # either party escalates to the arbiter (tier-2)

	# Platform operator surface for Tier-2 dispute rulings (OPERATOR_PUBKEYS-gated; a Nostr login, not a role).
	namespace :admin do
		resources :disputes, only: %i[index] do
			member { post :rule }
		end
	end

	# Defines the root path route ("/")
	root "pages#home"
end
