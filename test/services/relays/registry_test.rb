# frozen_string_literal: true

require "test_helper"

module Relays
	class RegistryTest < ActiveSupport::TestCase
		setup { Relays::Registry.instance.clear }
		teardown { Relays::Registry.instance.clear }

		def spec(id, kinds: [ 1 ]) = Relays::Subscription.new(id:, kinds:, ingest: nil)

		test "register stores by id and exposes all + find" do
			registry = Relays::Registry.instance
			a = registry.register(spec("a"))
			registry.register(spec("b"))

			assert_equal a, registry.find("a")
			assert_equal %w[a b], registry.all.map(&:id).sort
		end

		test "registering the same id replaces the prior spec" do
			registry = Relays::Registry.instance
			registry.register(spec("a"))
			registry.register(spec("a", kinds: [ 30_402 ]))

			assert_equal [ 30_402 ], registry.find("a").kinds
			assert_equal 1, registry.all.size
		end

		test "find returns nil for an unregistered id" do
			assert_nil Relays::Registry.instance.find("missing")
		end
	end
end
