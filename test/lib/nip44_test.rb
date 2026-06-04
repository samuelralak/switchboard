# frozen_string_literal: true

require "test_helper"

# Runs the official NIP-44 v2 test vectors (paulmillr/nip44, SHA256-pinned) against
# our pure-Ruby Nip44 module: ECDH conversation keys, per-message key derivation,
# the padding scheme, full encrypt/decrypt (incl. the 65535-byte max), and every
# documented invalid case. If the vendored vectors ever change, setup fails loudly.
class Nip44Test < ActiveSupport::TestCase
	VECTORS_PATH = Rails.root.join("test/fixtures/files/nip44.vectors.json")
	VECTORS_SHA256 = "269ed0f69e4c192512cc779e78c555090cebc7c785b609e338a62afc3ce25040"

	setup do
		raw = File.binread(VECTORS_PATH)
		assert_equal VECTORS_SHA256, Digest::SHA256.hexdigest(raw), "vendored NIP-44 vectors changed"
		v2 = JSON.parse(raw).fetch("v2")
		@valid = v2.fetch("valid")
		@invalid = v2.fetch("invalid")
	end

	test "calc_padded_len matches the spec for every bucket" do
		@valid["calc_padded_len"].each do |unpadded, expected|
			assert_equal expected, Nip44.send(:padded_length, unpadded), "padded_length(#{unpadded})"
		end
	end

	test "conversation_key derives via ECDH then HKDF-extract" do
		@valid["get_conversation_key"].each do |c|
			assert_equal c["conversation_key"], Nip44.conversation_key(c["sec1"], c["pub2"]).unpack1("H*")
		end
	end

	# R2 regression: NIP-44 step 7 (utf8_decode) requires the recovered plaintext be valid UTF-8.
	# A MAC-valid payload whose plaintext is not valid UTF-8 must fail closed as a decrypt error.
	test "decrypt rejects a plaintext that is not valid UTF-8" do
		c = @valid["get_conversation_key"].first
		ck = Nip44.conversation_key(c["sec1"], c["pub2"])
		payload = Nip44.encrypt("\xFF\xFE".b, ck)
		assert_raises(Nip44::Error) { Nip44.decrypt(payload, ck) }
	end

	test "message_keys split the HKDF-expand output 32/12/32" do
		group = @valid["get_message_keys"]
		ck = hex(group["conversation_key"])
		group["keys"].each do |k|
			chacha_key, chacha_nonce, hmac_key = Nip44.send(:message_keys, ck, hex(k["nonce"]))
			assert_equal k["chacha_key"], chacha_key.unpack1("H*")
			assert_equal k["chacha_nonce"], chacha_nonce.unpack1("H*")
			assert_equal k["hmac_key"], hmac_key.unpack1("H*")
		end
	end

	test "encrypt produces the canonical payload and decrypt round-trips" do
		@valid["encrypt_decrypt"].each do |c|
			ck = hex(c["conversation_key"])
			assert_equal c["payload"], Nip44.encrypt(c["plaintext"], ck, nonce: hex(c["nonce"]))
			assert_equal c["plaintext"], Nip44.decrypt(c["payload"], ck)
		end
	end

	test "encrypt and decrypt handle long messages up to the maximum" do
		@valid["encrypt_decrypt_long_msg"].each do |c|
			ck = hex(c["conversation_key"])
			plaintext = c["pattern"] * c["repeat"]
			assert_equal c["plaintext_sha256"], Digest::SHA256.hexdigest(plaintext)
			payload = Nip44.encrypt(plaintext, ck, nonce: hex(c["nonce"]))
			assert_equal c["payload_sha256"], Digest::SHA256.hexdigest(payload)
			assert_equal plaintext, Nip44.decrypt(payload, ck)
		end
	end

	test "decrypt rejects every malformed payload" do
		@invalid["decrypt"].each do |c|
			assert_raises(Nip44::Error, c["note"]) { Nip44.decrypt(c["payload"], hex(c["conversation_key"])) }
		end
	end

	test "encrypt rejects out-of-range plaintext lengths" do
		ck = SecureRandom.bytes(32)
		@invalid["encrypt_msg_lengths"].each do |length|
			assert_raises(Nip44::Error, "length #{length}") { Nip44.encrypt("a" * length, ck) }
		end
	end

	test "conversation_key rejects invalid keys" do
		@invalid["get_conversation_key"].each do |c|
			assert_raises(Nip44::Error, c["note"]) { Nip44.conversation_key(c["sec1"], c["pub2"]) }
		end
	end

	private

	def hex(string) = [ string ].pack("H*")
end
