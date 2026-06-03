# frozen_string_literal: true

source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"

# Load environment variables from .env files (development & test only) [https://github.com/bkeepers/dotenv]
gem "dotenv-rails", "~> 3.2", groups: %i[development test]
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Tailwind CSS v4 via the standalone CLI, no Node required [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails", "~> 4.4"
# Flexible form builder with full markup control [https://github.com/heartcombo/simple_form]
gem "simple_form", "~> 5.4"
# Reusable, testable, encapsulated view components [https://viewcomponent.org]
gem "view_component", "~> 4.11"

# --- Nostr connectivity (server-side relay client) ---
gem "nostr", "~> 0.7"            # NIP-01 events, BIP-340 Schnorr verification, bech32 (NIP-19)
gem "faye-websocket", "~> 0.12"  # WebSocket client for outbound relay connections
gem "eventmachine", "~> 1.2"     # reactor powering the persistent relay connections

# --- Service layer (dry-rb: typed initializers, validation, types, configuration) ---
gem "dry-initializer", "~> 3.2"
gem "dry-validation", "~> 1.11"
gem "dry-types", "~> 1.8"
gem "dry-configurable", "~> 1.4"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

group :development, :test do
	# See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
	gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

	# Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
	gem "bundler-audit", require: false

	# Static analysis for security vulnerabilities [https://brakemanscanner.org/]
	gem "brakeman", require: false

	# Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
	gem "rubocop-rails-omakase", require: false
end

group :development do
	# Use console on exceptions pages [https://github.com/rails/web-console]
	gem "web-console"
end

group :test do
	# Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
	gem "capybara"
	gem "selenium-webdriver"
end
