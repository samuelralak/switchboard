# frozen_string_literal: true

require "singleton"

module Relays
	# The process-wide set of ingest Subscriptions the relay subsystem serves. Consumers register their spec
	# at boot (config/initializers/relays.rb); Relays::Sync reads it to wire the live subscriptions and route
	# inbound events, and Relays::Reconcile reads it to backfill each spec onto a newly added relay. Singleton
	# + Mutex mirrors NostrClient::Manager: one shared, thread-safe table per process.
	class Registry
		include Singleton

		def initialize
			@subscriptions = {}
			@mutex = Mutex.new
		end

		# Register (or replace, keyed by id) a Subscription. Idempotent across dev code reloads.
		def register(subscription)
			@mutex.synchronize { @subscriptions[subscription.id] = subscription }
			subscription
		end

		def all = @mutex.synchronize { @subscriptions.values }
		def find(id) = @mutex.synchronize { @subscriptions[id] }
		def clear = @mutex.synchronize { @subscriptions.clear }
	end
end
