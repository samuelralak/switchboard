# frozen_string_literal: true

require "test_helper"

module Messages
	# Ruby-side seal -> wrap -> unwrap round trip, plus the structural NIP-59 invariants.
	class GiftWrapRoundTripTest < ActiveSupport::TestCase
		def setup
			@author = Nostr::Keygen.new.generate_key_pair
			@recipient = Nostr::Keygen.new.generate_key_pair
		end

		def pub(keypair) = keypair.public_key.to_s
		def priv(keypair) = keypair.private_key.to_s

		def build_rumor(content)
			Messages::BuildRumor.call(author_pubkey: pub(@author), content:, recipients: [ pub(@recipient) ])
		end

		test "seals, wraps, and unwraps back to the original rumor" do
			rumor = build_rumor("are you going?")

			seal = Messages::Seal.call(rumor:, author_private_key: priv(@author), recipient_pubkey: pub(@recipient))
			assert_equal Events::Kinds::SEAL, seal["kind"]
			assert_equal [], seal["tags"]
			assert_equal pub(@author), seal["pubkey"]

			wrap = Messages::GiftWrap.call(seal:, recipient_pubkey: pub(@recipient))
			assert_equal Events::Kinds::GIFT_WRAP, wrap["kind"]
			assert_equal [ [ "p", pub(@recipient) ] ], wrap["tags"]
			assert_not_equal pub(@author), wrap["pubkey"] # ephemeral key, not the author

			out = Messages::Unwrap.call(gift_wrap: wrap, recipient_private_key: priv(@recipient))
			assert_equal rumor, out
		end

		test "uses a fresh ephemeral key for each wrap of the same seal" do
			rumor = build_rumor("x")
			seal = Messages::Seal.call(rumor:, author_private_key: priv(@author), recipient_pubkey: pub(@recipient))

			w1 = Messages::GiftWrap.call(seal:, recipient_pubkey: pub(@recipient))
			w2 = Messages::GiftWrap.call(seal:, recipient_pubkey: pub(@recipient))

			assert_not_equal w1["pubkey"], w2["pubkey"]
			assert_not_equal w1["id"], w2["id"]
		end

		test "round-trips non-ASCII content with UTF-8 preserved" do
			rumor = build_rumor("héllo 世界 🎉")
			seal = Messages::Seal.call(rumor:, author_private_key: priv(@author), recipient_pubkey: pub(@recipient))
			wrap = Messages::GiftWrap.call(seal:, recipient_pubkey: pub(@recipient))
			out = Messages::Unwrap.call(gift_wrap: wrap, recipient_private_key: priv(@recipient))

			assert_equal rumor, out
			assert_equal Encoding::UTF_8, out["content"].encoding
		end
	end
end
