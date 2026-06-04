# frozen_string_literal: true

require "test_helper"

module Operational
	class PublishTest < ActiveSupport::TestCase
		test "signs with the R_op key and broadcasts the event to the relay manager" do
			keypair = Nostr::Keygen.new.generate_key_pair
			signer = Operational::Signer.new(private_key: keypair.private_key.to_s)
			published = nil
			manager = Object.new
			manager.define_singleton_method(:publish) { |event| published = event; [ :ok ] }

			kind = Events::Kinds::RELAY_LIST_DM
			result = Operational::Publish.call(kind:, tags: [ %w[relay wss://r.example] ], signer:, manager:)

			assert_equal [ :ok ], result
			assert_equal kind, published["kind"]
			assert_equal keypair.public_key.to_s, published["pubkey"]
			assert_includes published["tags"], %w[relay wss://r.example]
		end
	end
end
