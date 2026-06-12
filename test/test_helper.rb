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

		# Persist an escrow order for tests; defaults to a fresh catalog order in awaiting_funding.
		def build_order(**overrides)
			Order.create!(**order_defaults, **overrides)
		end

		def order_defaults
			{
				entry_point: Orders::EntryPoints::CATALOG_ORDER,
				current_state: Orders::States::AWAITING_FUNDING,
				tier: Orders::Tiers::TIER1_HTLC,
				amount_sats: 1_000,
				listing_coordinate: "30402:#{SecureRandom.hex(32)}:svc",
				mint_url: "http://127.0.0.1:3338",
				dedupe_key: SecureRandom.hex(16),
				funding_deadline_at: 1.hour.from_now,
				consumer_pubkey: SecureRandom.hex(32),
				provider_pubkey: SecureRandom.hex(32)
			}
		end

		# Fund an order via Orders::Funding with a known preimage; returns [ order, preimage, hashlock ].
		def fund_order(order = build_order, preimage: SecureRandom.hex(32), locktime: 1.hour.from_now)
			hashlock = ::Digest::SHA256.hexdigest([ preimage ].pack("H*"))
			point = -> { "02#{SecureRandom.hex(32)}" }
			with_unspent_checkstate do
				Orders::Funding.call(
					order:, mint_url: order.mint_url, hashlock:, locktime:, lock_pubkey: point.call,
					refund_pubkey: point.call, proofs: [ { y: point.call, amount: order.amount_sats } ]
				)
			end
			[ order.reload, preimage, hashlock ]
		end

		# A fixed test arbiter key (NEVER a real key). Provisions the platform arbiter for Tier-2 tests.
		TEST_ARBITER_PRIVKEY = "22" * 32

		# Run the block with the platform arbiter key provisioned in ENV (Tier-2 enabled), then restore.
		def with_arbiter_key(privkey = TEST_ARBITER_PRIVKEY)
			previous = ENV.fetch("ESCROW_TIER2_ARBITER_PRIVKEY", nil)
			ENV["ESCROW_TIER2_ARBITER_PRIVKEY"] = privkey
			yield
		ensure
			ENV["ESCROW_TIER2_ARBITER_PRIVKEY"] = previous
		end

		# The compressed arbiter pubkey for the test key (derived directly, independent of ENV).
		def platform_arbiter_pubkey(privkey = TEST_ARBITER_PRIVKEY)
			Escrow::ArbiterSigner.new(private_key: privkey).pubkey
		end

		# Fund a Tier-2 (2-of-3 arbiter) order via Orders::Funding; returns the reloaded order. The locktime
		# clears the Tier-2 min-lead and the amount sits under the Tier-2 cap.
		def fund_tier2_order(order = nil, locktime: 4.days.from_now)
			order ||= build_order(tier: Orders::Tiers::TIER2_ARBITER, amount_sats: 1_000)
			point = -> { "02#{SecureRandom.hex(32)}" }
			params = {
				mint_url: order.mint_url, locktime:, lock_pubkey: point.call, refund_pubkey: point.call,
				arbiter_pubkey: platform_arbiter_pubkey, required_signatures: 2,
				proofs: [ { y: point.call, amount: order.amount_sats } ]
			}
			with_arbiter_key { with_unspent_checkstate { Orders::Funding.call(order:, **params) } }
			order.reload
		end

		# Fund a Tier-2 order whose proof Ys are the NUT-00 points of `secrets`, so the arbiter binding is
		# exercised against genuine secret -> Y mappings rather than random Ys. Optionally pin the parties.
		def fund_tier2_order_with_secrets(secrets, provider: nil, consumer: nil)
			attrs = { tier: Orders::Tiers::TIER2_ARBITER, amount_sats: secrets.size }
			attrs[:provider_pubkey] = provider if provider
			attrs[:consumer_pubkey] = consumer if consumer
			order = build_order(**attrs)
			point = -> { "02#{SecureRandom.hex(32)}" }
			params = {
				mint_url: order.mint_url, locktime: 4.days.from_now, lock_pubkey: point.call, refund_pubkey: point.call,
				arbiter_pubkey: platform_arbiter_pubkey, required_signatures: 2,
				proofs: secrets.map { |secret| { y: Cashu::Actions::HashToCurve.call(secret:), amount: 1 } }
			}
			with_arbiter_key { with_unspent_checkstate { Orders::Funding.call(order:, **params) } }

			order.reload
		end

		# A kind-30402 listing/request event by a specific author, carrying a NIP-99 price/budget tag.
		def classified_event(pubkey:, marker:, price: 1_000, currency: "sat", d: SecureRandom.hex(4), extra_tags: [])
			tags = [ [ "d", d ], [ "title", "Svc" ], [ "t", marker ], [ "price", price.to_s, currency ] ] + extra_tags
			Event.create!(
				event_id: SecureRandom.hex(32), pubkey:, sig: SecureRandom.hex(64), kind: Events::Kinds::CLASSIFIED,
				content: "Svc", tags:, nostr_created_at: Time.current, raw_event: { "id" => SecureRandom.hex(32) }
			)
		end

		def coordinate_for(event) = "#{event.kind}:#{event.pubkey}:#{event.d_tag}"

		# Minitest 6 dropped stub/mock; shadow Cashu::Checkstate.call to return `result` for the block.
		def with_checkstate(result)
			Cashu::Checkstate.singleton_class.define_method(:call) { |**| result }
			yield
		ensure
			Cashu::Checkstate.singleton_class.send(:remove_method, :call)
		end

		# Funding checkstates the proofs; shadow an all-UNSPENT mint so a funding test needs no live mint.
		def with_unspent_checkstate(&block)
			state = Cashu::ProofState.new(y: "02#{SecureRandom.hex(32)}", state: "UNSPENT", witness: nil)
			with_checkstate([ state ], &block)
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

		# A NIP-98 (kind 27235) HTTP-auth event. A fresh keypair by default; pass one to sign as a known pubkey.
		def sign_nip98(tags:, created_at: Time.now.to_i, kind: Events::Kinds::HTTP_AUTH, content: "", keypair: Nostr::Keygen.new.generate_key_pair)
			sign_event(kind:, tags:, content:, created_at:, keypair:)
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
