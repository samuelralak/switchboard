# frozen_string_literal: true

require "test_helper"

module Messages
	# Shared NIP-59 round-trip helpers for the Unwrap test classes.
	module UnwrapTestSupport
		def setup
			@author = Nostr::Keygen.new.generate_key_pair
			@recipient = Nostr::Keygen.new.generate_key_pair
		end

		def pub(keypair) = keypair.public_key.to_s
		def priv(keypair) = keypair.private_key.to_s

		def build_rumor(content)
			Messages::BuildRumor.call(author_pubkey: pub(@author), content:, recipients: [ pub(@recipient) ])
		end

		# A hand-built rumor (authored by @author so it passes impersonation) for malformed input.
		def custom_rumor(overrides)
			base = { "pubkey" => pub(@author), "created_at" => 1, "kind" => 14, "tags" => [], "content" => "hi" }
			rumor = base.merge(overrides)
			rumor["id"] = Events::Actions::ComputeCanonicalId.call(event: rumor)
			rumor
		end

		def wrap_for(rumor, author_private_key)
			seal = Messages::Seal.call(rumor:, author_private_key:, recipient_pubkey: pub(@recipient))
			Messages::GiftWrap.call(seal:, recipient_pubkey: pub(@recipient))
		end

		def unwrap(gift_wrap, recipient = @recipient)
			Messages::Unwrap.call(gift_wrap:, recipient_private_key: priv(recipient))
		end
	end

	class UnwrapTest < ActiveSupport::TestCase
		include UnwrapTestSupport

		# Published NIP-59 example (nips/59.md, vendored): decrypting a nostr-tools-built wrap
		# proves cross-implementation interop end to end.
		VECTOR = JSON.parse(Rails.root.join("test/fixtures/files/nip59.vector.json").read).freeze

		test "decrypts and validates the NIP-59 published gift wrap" do
			wrap = VECTOR["gift_wrap"]
			rumor = Messages::Unwrap.call(gift_wrap: wrap, recipient_private_key: VECTOR["recipient_private_key"])
			expected = VECTOR["expected_rumor"]

			assert_equal expected["content"], rumor["content"]
			assert_equal expected["kind"], rumor["kind"]
			assert_equal expected["pubkey"], rumor["pubkey"]
			assert_equal expected["id"], rumor["id"]
		end

		test "rejects a forged author (seal.pubkey != rumor.pubkey)" do
			forger = Nostr::Keygen.new.generate_key_pair
			error = assert_raises(Messages::UnwrapError) { unwrap(wrap_for(build_rumor("forged"), priv(forger))) }
			assert_match(/impersonation/, error.message)
		end

		test "rejects a signed rumor" do
			rumor = build_rumor("hi")
			rumor["sig"] = "0" * 128
			error = assert_raises(Messages::UnwrapError) { unwrap(wrap_for(rumor, priv(@author))) }
			assert_match(/unsigned/, error.message)
		end

		test "rejects a tampered rumor (id mismatch)" do
			rumor = build_rumor("original")
			rumor["content"] = "tampered" # id is now stale
			error = assert_raises(Messages::UnwrapError) { unwrap(wrap_for(rumor, priv(@author))) }
			assert_match(/id mismatch/, error.message)
		end

		test "rejects an undecryptable wrap (wrong recipient)" do
			wrap = wrap_for(build_rumor("hi"), priv(@author))
			error = assert_raises(Messages::UnwrapError) { unwrap(wrap, Nostr::Keygen.new.generate_key_pair) }
			assert_match(/decrypt failed/, error.message)
		end

		test "rejects a gift wrap with a bad signature" do
			wrap = wrap_for(build_rumor("hi"), priv(@author))
			wrap["sig"] = "0" * 128
			assert_raises(Messages::UnwrapError) { unwrap(wrap) }
		end
	end

	# NIP-01/NIP-17 well-formedness guards the unsigned rumor would otherwise skip.
	class UnwrapGuardsTest < ActiveSupport::TestCase
		include UnwrapTestSupport

		test "rejects a rumor with malformed NIP-01 typing" do
			[ { "created_at" => "1" }, { "kind" => "14" }, { "content" => 123 } ].each do |bad|
				wrap = wrap_for(custom_rumor(bad), priv(@author))
				assert_match(/malformed/, assert_raises(Messages::UnwrapError) { unwrap(wrap) }.message)
			end
		end

		test "rejects a rumor with a NUL byte in its content" do
			wrap = wrap_for(custom_rumor("content" => "a#{0.chr}b"), priv(@author))
			assert_match(/null byte/, assert_raises(Messages::UnwrapError) { unwrap(wrap) }.message)
		end

		# Pins the reorder: the id is computed first, yet the sig guard still fires, and a NUL in
		# content does not crash the id recompute (JSON.generate escapes it).
		test "reaches the sig guard though the id is computed first, NUL-safe" do
			wrap = wrap_for(custom_rumor("content" => "a#{0.chr}b", "sig" => "0" * 128), priv(@author))
			assert_match(/unsigned/, assert_raises(Messages::UnwrapError) { unwrap(wrap) }.message)
		end

		test "strips unauthenticated extra keys, returning only the canonical fields" do
			out = unwrap(wrap_for(custom_rumor("evil" => "x"), priv(@author)))
			assert_equal %w[content created_at id kind pubkey tags], out.keys.sort
		end

		test "rejects an inner event that is not a kind-13 seal" do
			conversation_key = Nip44.conversation_key(priv(@author), pub(@recipient))
			content = Nip44.encrypt(JSON.generate(custom_rumor({})), conversation_key)
			fake = Events::Sign.call(private_key: priv(@author), kind: 14, tags: [], content:)
			wrap = Messages::GiftWrap.call(seal: fake, recipient_pubkey: pub(@recipient))
			assert_match(/seal: expected kind 13/, assert_raises(Messages::UnwrapError) { unwrap(wrap) }.message)
		end

		test "rejects an outer event that is not a kind-1059 gift wrap" do
			rumor = custom_rumor({})
			seal = Messages::Seal.call(rumor:, author_private_key: priv(@author), recipient_pubkey: pub(@recipient))
			secret_key = Nostr::Keygen.new.generate_key_pair.private_key.to_s
			content = Nip44.encrypt(JSON.generate(seal), Nip44.conversation_key(secret_key, pub(@recipient)))
			fake = Events::Sign.call(private_key: secret_key, kind: 1060, tags: [ [ "p", pub(@recipient) ] ], content:)
			assert_match(/gift wrap: expected kind 1059/, assert_raises(Messages::UnwrapError) { unwrap(fake) }.message)
		end

		# R1 regression: a MAC-valid inner layer that is not JSON must NOT leak its decrypted
		# plaintext into the UnwrapError message (which the central handler writes to the log).
		test "does not leak decrypted plaintext when an inner layer is not valid JSON" do
			secret = "SUPERSECRET-not-json {{{"
			content = Nip44.encrypt(secret, Nip44.conversation_key(priv(@author), pub(@recipient)))
			seal = Events::Sign.call(private_key: priv(@author), kind: 13, tags: [], content:)
			wrap = Messages::GiftWrap.call(seal:, recipient_pubkey: pub(@recipient))

			error = assert_raises(Messages::UnwrapError) { unwrap(wrap) }
			assert_match(/not valid JSON/, error.message)
			assert_not_includes error.message, "SUPERSECRET"
		end
	end
end
