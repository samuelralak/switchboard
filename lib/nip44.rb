# frozen_string_literal: true

require "openssl"
require "base64"
require "securerandom"

# NIP-44 v2 payload encryption: secp256k1 ECDH key agreement, HKDF key
# derivation, ChaCha20 encryption, and an HMAC-SHA256 authentication tag. This is
# the layer NIP-17 private messages and NIP-59 gift wraps build on; NIP-04's
# deprecated, unauthenticated AES-CBC is intentionally not used. Pure, stateless
# crypto: no IO, no logging, never persists keys or plaintext.
#
#   ck      = Nip44.conversation_key(my_priv_hex, their_xonly_pub_hex)
#   payload = Nip44.encrypt("hello", ck)   # => base64 String
#   text    = Nip44.decrypt(payload, ck)   # => "hello"
#
# Verified against the official NIP-44 v2 test vectors (see test/lib/nip44_test.rb).
module Nip44
	# Any encrypt/decrypt/parse/validation failure. Callers rescue Nip44::Error.
	class Error < StandardError; end

	VERSION = 2
	SALT = "nip44-v2" # HKDF-extract salt, fixed by the spec
	CURVE = "secp256k1"
	MIN_PLAINTEXT = 1
	MAX_PLAINTEXT = 65_535

	class << self
		# x-only pubkey (even-Y per BIP-340) -> ECDH shared X -> HKDF-extract -> 32-byte key.
		# HKDF-Extract with SHA256 is exactly HMAC(salt, IKM); OpenSSL has no extract-only KDF.
		def conversation_key(private_key_hex, public_key_hex)
			OpenSSL::HMAC.digest("SHA256", SALT, ecdh(private_key_hex, public_key_hex))
		end

		# plaintext: 1..65535 UTF-8 bytes. Returns the base64 v2 payload. The nonce is
		# injectable only so the test vectors can pin it; production must let it default.
		def encrypt(plaintext, conversation_key, nonce: SecureRandom.bytes(32))
			chacha_key, chacha_nonce, hmac_key = message_keys(conversation_key, nonce)
			ciphertext = chacha20(chacha_key, chacha_nonce, pad(plaintext))
			mac = hmac_aad(hmac_key, ciphertext, nonce)
			Base64.strict_encode64([ VERSION ].pack("C") + nonce + ciphertext + mac)
		end

		# payload: base64 v2 String. Returns the UTF-8 plaintext, or raises Nip44::Error.
		def decrypt(payload, conversation_key)
			nonce, ciphertext, mac = decode(payload)
			chacha_key, chacha_nonce, hmac_key = message_keys(conversation_key, nonce)
			raise Error, "invalid MAC" unless OpenSSL.fixed_length_secure_compare(hmac_aad(hmac_key, ciphertext, nonce), mac)

			unpad(chacha20(chacha_key, chacha_nonce, ciphertext))
		end

		private

		# ECDH shared-point X coordinate: 32 raw bytes, unhashed (the NIP-44/NIP-04
		# convention). Mirrors the nostr gem's NIP-04 path; the shared X is identical
		# for ±Y, so reconstructing the pubkey as compressed "02"+x is safe.
		def ecdh(private_key_hex, public_key_hex)
			group = OpenSSL::PKey::EC::Group.new(CURVE)
			private_bn = OpenSSL::BN.new(private_key_hex, 16)
			point = OpenSSL::PKey::EC::Point.new(group, OpenSSL::BN.new("02#{public_key_hex}", 16))
			OpenSSL::PKey::EC.new(ec_key_der(private_bn, point)).dh_compute_key(point)
		rescue OpenSSL::OpenSSLError => e
			raise Error, "invalid key (#{e.message})"
		end

		# A secp256k1 private key wrapped in the ASN.1/DER structure OpenSSL::PKey::EC expects.
		def ec_key_der(private_bn, point)
			fields = [ OpenSSL::ASN1::Integer.new(1) ]
			fields << OpenSSL::ASN1::OctetString(private_bn.to_s(2))
			fields << OpenSSL::ASN1::ObjectId(CURVE, 0, :EXPLICIT)
			fields << OpenSSL::ASN1::BitString(point.to_octet_string(:uncompressed), 1, :EXPLICIT)
			OpenSSL::ASN1::Sequence(fields).to_der
		end

		# RFC 5869 HKDF-Expand. Hand-rolled because OpenSSL::KDF.hkdf always re-extracts.
		def hkdf_expand(prk, info, length)
			blocks = (length + 31) / 32
			okm = "".b
			block = "".b
			(1..blocks).each do |i|
				block = OpenSSL::HMAC.digest("SHA256", prk, block + info + [ i ].pack("C"))
				okm << block
			end
			okm[0, length]
		end

		# Per-message keys: expand the conversation key over the nonce, split 32/12/32.
		def message_keys(conversation_key, nonce)
			keys = hkdf_expand(conversation_key, nonce, 76)
			[ keys[0, 32], keys[32, 12], keys[44, 32] ]
		end

		# ChaCha20, RFC 8439, counter 0. OpenSSL's "chacha20" wants a 16-byte IV: a
		# 4-byte little-endian block counter (0) followed by the 12-byte nonce.
		def chacha20(key, nonce, data)
			cipher = OpenSSL::Cipher.new("chacha20").encrypt
			cipher.key = key
			cipher.iv = "\x00\x00\x00\x00".b + nonce
			cipher.update(data) + cipher.final
		end

		# HMAC-SHA256 over (aad || ciphertext); the AAD is the 32-byte nonce.
		def hmac_aad(key, ciphertext, aad)
			raise Error, "invalid aad" unless aad.bytesize == 32

			OpenSSL::HMAC.digest("SHA256", key, aad + ciphertext)
		end

		# Obscure the plaintext length: u16-BE length prefix || plaintext || zero fill.
		def pad(plaintext)
			length = plaintext.bytesize
			raise Error, "invalid plaintext length" if length < MIN_PLAINTEXT || length > MAX_PLAINTEXT

			[ length ].pack("n") + plaintext.b + ("\x00".b * (padded_length(length) - length))
		end

		def unpad(padded)
			length = padded[0, 2].unpack1("n")
			text = padded[2, length] || "".b
			unless length.positive? && text.bytesize == length && padded.bytesize == 2 + padded_length(length)
				raise Error, "invalid padding"
			end

			# NIP-44 step 7 (utf8_decode): the recovered plaintext MUST be valid UTF-8.
			text.force_encoding("UTF-8").tap { |t| raise Error, "invalid utf-8" unless t.valid_encoding? }
		end

		# NIP-44 padding buckets: 32 bytes up to 32, then power-of-two-aligned chunks.
		def padded_length(unpadded)
			return 32 if unpadded <= 32

			next_power = 1 << (Integer(Math.log2(unpadded - 1)) + 1)
			chunk = next_power <= 256 ? 32 : next_power / 8
			chunk * (((unpadded - 1) / chunk) + 1)
		end

		# Decode a base64 v2 payload (string-level guards), then unpack its bytes.
		def decode(payload)
			raise Error, "unknown version" if payload.empty? || payload.start_with?("#")
			raise Error, "invalid payload size" unless payload.bytesize.between?(132, 87_472)

			unpack_envelope(decode64(payload))
		end

		# Validate the decoded bytes and split into [nonce, ciphertext, mac].
		def unpack_envelope(data)
			size = data.bytesize
			raise Error, "invalid data size" unless size.between?(99, 65_603)
			raise Error, "unknown version" unless data.getbyte(0) == VERSION

			[ data[1, 32], data[33, size - 65], data[size - 32, 32] ]
		end

		def decode64(payload)
			Base64.strict_decode64(payload)
		rescue ArgumentError
			raise Error, "invalid base64"
		end
	end
end
