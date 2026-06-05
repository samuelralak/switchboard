# frozen_string_literal: true

module Messages
	# Stores an opaque NIP-59 gift wrap (kind 1059) for its recipient, so the recipient can resume its
	# inbox on cold start. Validates the wrap is a well-formed, correctly-signed kind-1059 with a
	# recipient [p] tag, then persists it deduped by event id. NEVER decrypts (the server holds no
	# user key). Raises InvalidEventError on a malformed/forged wrap or a non-1059, so the open
	# deposit endpoint rejects junk without disclosing more.
	class StoreWrap < BaseService
		option :event, type: Types::Strict::Hash

		def call
			wrap = verified_wrap
			recipient = recipient_pubkey(wrap)
			# Dedup before the quota, so a re-deposit is never wedged out.
			InboxWrap.find_by(wrap_id: wrap["id"]) || store(wrap, recipient)
		end

		private

		def store(wrap, recipient)
			raise InboxFullError if inbox_full?(recipient)

			InboxWrap.create_or_find_by!(wrap_id: wrap["id"]) do |record|
				record.recipient_pubkey = recipient
				record.wrap = canonical(wrap)
				record.nostr_created_at = Time.zone.at(wrap["created_at"])
				record.expires_at = retention_horizon(wrap)
			end
		end

		def verified_wrap
			wrap = Events::Verify.call(event_data: event)
			raise InvalidEventError, "not a gift wrap" unless wrap["kind"] == Events::Kinds::GIFT_WRAP

			wrap
		end

		# Store only the canonical Nostr event fields; drop any non-standard extra keys (not signed over).
		def canonical(wrap)
			wrap.slice("id", "pubkey", "created_at", "kind", "tags", "content", "sig")
		end

		# The single NIP-17 routing tag; without a valid recipient the wrap is undeliverable.
		def recipient_pubkey(wrap)
			pubkey = wrap["tags"].find { |tag| tag.first == "p" }&.at(1)
			raise InvalidEventError, "gift wrap missing a recipient p tag" unless pubkey.to_s.match?(/\A[a-f0-9]{64}\z/)

			pubkey
		end

		# Earlier of our retention cap and the wrap's own NIP-40 expiration (disappearing messages).
		def retention_horizon(wrap)
			cap = Time.current + InboxWrap::RETENTION
			expiration = wrap["tags"].find { |tag| tag.first == "expiration" }&.at(1)
			expiration.to_s.match?(/\A\d+\z/) ? [ cap, Time.zone.at(expiration.to_i) ].min : cap
		end

		# Identity-free storage cap per recipient; dedup keeps re-deposits from counting twice.
		def inbox_full?(recipient)
			InboxWrap.for_recipient(recipient).unexpired.count >= InboxWrap::PER_RECIPIENT_QUOTA
		end
	end
end
