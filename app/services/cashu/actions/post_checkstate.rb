# frozen_string_literal: true

require "net/http"

module Cashu
	module Actions
		# POST a NUT-07 checkstate request to a mint and return the raw response body. Caps the body size and
		# the timeout to bound a misbehaving mint; raises MintError on any transport/protocol failure, so a
		# settlement is never inferred from a bad response. Observe-only; the caller allowlist-guards the mint.
		class PostCheckstate < BaseService
			MAX_BODY = 1_000_000 # a checkstate response covers a handful of proofs; cap it to bound a bad mint
			TIMEOUT = 5

			option :mint_url, type: Types::Strict::String
			option :ys, type: Types::Strict::Array.of(Types::Strict::String)

			def call
				response = post
				raise MintError, "mint checkstate returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)
				raise MintError, "mint checkstate body too large" if response.body.to_s.bytesize > MAX_BODY

				response.body
			rescue MintError
				raise
			rescue StandardError => e
				raise MintError, "mint checkstate failed: #{e.class}: #{e.message}"
			end

			private

			def post
				uri = URI("#{mint_url}/v1/checkstate")
				client(uri).post(uri.request_uri, { Ys: ys }.to_json, "Content-Type" => "application/json")
			end

			def client(uri)
				http = Net::HTTP.new(uri.host, uri.port)
				http.use_ssl = uri.scheme == "https"
				http.open_timeout = http.read_timeout = TIMEOUT
				http
			end
		end
	end
end
