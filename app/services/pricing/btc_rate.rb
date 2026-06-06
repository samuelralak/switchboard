# frozen_string_literal: true

require "net/http"

module Pricing
	# The current BTC/USD spot price for the studio's fiat hint, cached so a page render never blocks on (or
	# hammers) the upstream feed. Returns a Float (USD per BTC) or nil when the feed is unavailable; callers
	# treat nil as "hide the hint". Display-only convenience, not custodial or security-sensitive.
	class BtcRate < BaseService
		CACHE_KEY = "pricing:btc_usd"
		TTL = 10.minutes
		SOURCE = "https://api.coinbase.com/v2/prices/BTC-USD/spot"

		def call
			Rails.cache.fetch(CACHE_KEY, expires_in: TTL, skip_nil: true) { fetch_rate }
		end

		private

		def fetch_rate
			return nil if Rails.env.test? # display-only; never make an external call from the test suite

			uri = URI(SOURCE)
			http = Net::HTTP.new(uri.host, uri.port)
			http.use_ssl = true
			http.open_timeout = 3
			http.read_timeout = 3
			response = http.get(uri.request_uri, "Accept" => "application/json")
			response.is_a?(Net::HTTPSuccess) ? parse(response.body) : nil
		rescue StandardError
			nil # a flaky feed must never break the studio; the hint simply hides
		end

		# Coinbase spot shape: { "data": { "amount": "95000.00", "base": "BTC", "currency": "USD" } }.
		def parse(body)
			Float(JSON.parse(body).dig("data", "amount"))
		rescue StandardError
			nil
		end
	end
end
