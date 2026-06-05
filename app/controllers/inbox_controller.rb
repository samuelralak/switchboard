# frozen_string_literal: true

# The opaque NIP-17 inbox cache. Two trust models share one path:
#   POST /inbox -- ANONYMOUS deposit, like a relay accepting an EVENT, so the gift wrap's
#     sender-hiding survives. No session, no CSRF token, rate-limited and size-capped. A session-
#     or NIP-98-authenticated deposit would resolve to the sender's real pubkey and hand the server
#     a sender->recipient graph, defeating NIP-17, so the deposit must stay identity-free.
#   GET /inbox -- SESSION-authenticated, recipient-only. The signed-in cookie already proves the
#     fetcher's pubkey (Current.user), so no per-request NIP-98 signing is needed.
# The server never decrypts a wrap; it learns no more than any relay (recipient p-tag + opaque blob).
# Privacy invariant: the deposit path must not persist or log the source IP (the record has no IP
# column; rate_limit's IP key is ephemeral). Residual leak: the row's wall-clock created_at, used for
# the cursor, retains arrival time the randomized 1059 timestamp tries to hide; bounded by RETENTION.
# This store is reachable only by Switchboard's own client; interoperable delivery is the recipient's
# kind-10050 inbox relays. See docs/messaging-architecture.md.
class InboxController < ApplicationController
	PAGE_LIMIT = 500
	# Coarse transport guard so a giant body never reaches JSON.parse; the real content bound is the
	# NIP-44 plaintext cap enforced in the crypto layer, well below this.
	MAX_WRAP_BYTES = 256 * 1024

	skip_forgery_protection only: :create
	before_action :require_recipient, only: :index
	# Keyed by a hashed IP, not the raw IP, to honor the no-source-IP-retention invariant (the key
	# lives transiently in Solid Cache).
	rate_limit to: 60, within: 1.minute, only: :create, by: -> { hashed_ip }

	# GET /inbox -> the signed-in recipient's opaque wraps strictly after ?cursor (a "created_at|id" keyset).
	def index
		wraps = InboxWrap.for_recipient(Current.user.pubkey).unexpired.after_cursor(*cursor).chronological.limit(PAGE_LIMIT)
		render json: { wraps: wraps.map(&:wrap), cursor: next_cursor(wraps.last) }
	end

	# POST /inbox -> deposit one opaque gift wrap (anonymous; validated, deduped, size-capped, rate-limited).
	def create
		Messages::StoreWrap.call(event: wrap_param)
		head :created
	rescue InvalidEventError
		head :unprocessable_content
	rescue InboxFullError
		head :insufficient_storage
	end

	private

	# Session is the recipient's identity; a JSON consumer gets 401, not require_login's HTML redirect.
	def require_recipient
		head :unauthorized unless signed_in?
	end

	# Salted so the raw source IP is never the cache key (deposit-path privacy invariant).
	def hashed_ip
		OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, request.remote_ip)
	end

	def wrap_param
		raise InvalidEventError, "wrap too large" if oversized?

		parsed = JSON.parse(request.raw_post)
		raise InvalidEventError, "wrap is not an object" unless parsed.is_a?(Hash)

		parsed
	rescue JSON::ParserError
		raise InvalidEventError, "malformed wrap"
	end

	# Reject before parsing so a giant body never reaches JSON.parse.
	def oversized?
		request.content_length.to_i > MAX_WRAP_BYTES || request.raw_post.bytesize > MAX_WRAP_BYTES
	end

	# A composite "created_at|id" keyset, so a page boundary that splits wraps sharing a created_at
	# never drops one. Returns [time, id]; a missing/malformed cursor reads from the start.
	def cursor
		raw = params[:cursor].to_s
		return [ nil, nil ] if raw.blank?

		time, id = raw.split("|", 2)
		[ Time.iso8601(time), id ]
	rescue ArgumentError
		[ nil, nil ]
	end

	def next_cursor(row)
		row && "#{row.created_at.iso8601(6)}|#{row.id}"
	end
end
