# frozen_string_literal: true

require "test_helper"

module Users
	class RelayListFetchTest < ActiveSupport::TestCase
		R = Events::Kinds::RELAY_LIST

		def event(pubkey:, created_at:, id: SecureRandom.hex(32), kind: R)
			{ "id" => id, "pubkey" => pubkey, "kind" => kind, "created_at" => created_at }
		end

		# Stub the relay I/O (Relays::FetchEvents) to return canned events; exercise the pick/filter layer.
		def pick_from(events, pubkey:)
			Relays::FetchEvents.define_singleton_method(:call) { |**| events }
			Users::RelayListFetch.call(pubkey:)
		ensure
			Relays::FetchEvents.singleton_class.send(:remove_method, :call)
		end

		test "picks the latest of MY kind:10002 and filters foreign pubkeys and wrong kinds" do
			pk = SecureRandom.hex(32)
			mine_old = event(pubkey: pk, created_at: 100, id: "aaaa")
			mine_new = event(pubkey: pk, created_at: 200, id: "bbbb")
			foreign = event(pubkey: SecureRandom.hex(32), created_at: 300) # other pubkey: dropped
			wrong = event(pubkey: pk, created_at: 400, kind: 1) # wrong kind: dropped

			assert_equal "bbbb", pick_from([ mine_old, mine_new, foreign, wrong ], pubkey: pk)["id"]
		end

		test "breaks a created_at tie on the lexicographically lower id" do
			pk = SecureRandom.hex(32)
			hi = event(pubkey: pk, created_at: 200, id: "ffff")
			lo = event(pubkey: pk, created_at: 200, id: "0000")

			assert_equal "0000", pick_from([ hi, lo ], pubkey: pk)["id"]
		end

		test "returns nil when no matching event is found" do
			pk = SecureRandom.hex(32)

			assert_nil pick_from([ event(pubkey: SecureRandom.hex(32), created_at: 1) ], pubkey: pk)
		end
	end
end
