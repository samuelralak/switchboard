# frozen_string_literal: true

module Shared
	# True when a string / array / hash structure contains a NUL byte anywhere. Nostr events
	# are stored verbatim in a jsonb column that cannot hold \x00, so Events::Verify (signed
	# layers) and Messages::Unwrap (the unsigned rumor) reject it at the crypto boundary rather
	# than letting it surface later as a PG error at write time.
	class ContainsNullByte < BaseService
		option :value

		def call
			scan(value)
		end

		private

		def scan(node)
			case node
			when String then node.bytes.include?(0)
			when Array  then node.any? { |item| scan(item) }
			when Hash   then node.any? { |key, val| scan(key) || scan(val) }
			else false
			end
		end
	end
end
