# frozen_string_literal: true

require "test_helper"

# Drives the real importmap JS in headless Chrome (Capybara + Selenium). Used to vector-test the
# browser NIP-17 crypto against the same fixtures the Ruby spine uses, so the two stay byte-aligned.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
	driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

	# turbo-rails patches #visit to wait for every <turbo-cable-stream-source> to report [connected].
	# Turbo Cable is not wired for system tests, so that wait errors on the catalog's live-update
	# stream source. These tests exercise client-side crypto, not Turbo Cable, so skip the wait.
	def connect_turbo_cable_stream_sources(*) = nil
end
