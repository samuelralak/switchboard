# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "nostr"

module ActiveSupport
	class TestCase
		# Run tests in parallel with specified workers
		parallelize(workers: :number_of_processors)

		# Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
		fixtures :all

		# Persist a catalog event for tests; defaults to a classified (NIP-99) listing.
		def build_event(kind: Events::Kinds::CLASSIFIED, title: "Service", content: nil, d: "svc",
										created_at: Time.current, expiration: nil, extra_tags: [])
			tags = []
			tags << [ "d", d ] << [ "title", title ] if Events::Kinds.addressable?(kind)
			tags.concat(extra_tags)
			tags << [ "expiration", expiration.to_i.to_s ] if expiration
			Event.create!(
				event_id: SecureRandom.hex(32),
				pubkey: SecureRandom.hex(32),
				sig: SecureRandom.hex(64),
				kind:,
				content: content || title,
				tags:,
				nostr_created_at: created_at,
				raw_event: { "id" => SecureRandom.hex(32) }
			)
		end

		# Builds and BIP-340-signs an arbitrary Nostr event; returns the wire hash (string keys).
		# Pass a keypair to control the author (e.g. to assert on its pubkey).
		def sign_event(kind:, tags: [], content: "", created_at: Time.now.to_i, keypair: Nostr::Keygen.new.generate_key_pair)
			pubkey = keypair.public_key.to_s
			id = ::Digest::SHA256.hexdigest(::JSON.generate([ 0, pubkey, created_at, kind, tags, content ]))
			sig = Nostr::Crypto.new.sign_message(id, keypair.private_key).to_s
			{
				"id" => id, "pubkey" => pubkey, "created_at" => created_at, "kind" => kind,
				"tags" => tags, "content" => content, "sig" => sig
			}
		end

		# A NIP-98 (kind 27235) HTTP-auth event with a fresh keypair. Shared by the auth tests.
		def sign_nip98(tags:, created_at: Time.now.to_i, kind: Events::Kinds::HTTP_AUTH, content: "")
			sign_event(kind:, tags:, content:, created_at:)
		end

		# NIP-98 u/method tags, plus an optional `challenge` (session path) or `payload` hash.
		def nip98_tags(url:, http_method: "POST", challenge: nil, payload: nil)
			tags = [ [ "u", url ], [ "method", http_method ] ]
			tags << [ "challenge", challenge ] if challenge
			tags << [ "payload", payload ] if payload
			tags
		end
	end
end
