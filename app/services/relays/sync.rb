# frozen_string_literal: true

module Relays
	# Boots the relay ingest process (the `relay:boot` task): wires the inbound-event router, registers every
	# consumer's live subscription, opens the seed connections, and arms the periodic reconcile that folds
	# logged-in users' write relays into the set. The handler and subscriptions are registered BEFORE any
	# connection opens, so no inbound EVENT is dropped. The reconcile tick runs on the reactor thread, so its
	# DB work is wrapped in the Rails executor and never allowed to raise out and kill the timer.
	class Sync
		extend Dry::Initializer

		option :registry, default: -> { Registry.instance }, reader: :private
		option :manager, default: -> { NostrClient.manager }, reader: :private
		option :reconcile_interval, default: -> { NostrClient.configuration.reconcile_interval_seconds }, reader: :private

		delegate :stop, to: :NostrClient

		def start
			route_events
			subscribe
			NostrClient.start
			open_seed_connections
			schedule_reconcile
			self
		end

		private

		# One global handler routes every inbound event to its subscription's ingest by subscription_id, so a
		# second subscription can never cross-feed the wrong consumer.
		def route_events
			manager.on_event { |connection, subscription_id, event| dispatch(connection, subscription_id, event) }
		end

		# Defer the ingest onto Solid Queue (the work runs later in the jobs process); the perform_later enqueue
		# itself runs here on the reactor thread, wrapped in the Rails executor so its DB access is safe (it
		# does NOT move threads). An unknown subscription_id (none registered) is ignored rather than enqueued.
		def dispatch(connection, subscription_id, event)
			subscription = registry.find(subscription_id) or return

			Rails.application.executor.wrap { subscription.enqueue(event, connection.url) }
		rescue StandardError => e
			Rails.logger.error("[Relays::Sync] dispatch error: #{e.class}: #{e.message}")
		end

		# Record every consumer's filters before connecting; each relay sends its REQ on open (and on every
		# later add_connection, via Manager replay).
		def subscribe
			subscriptions = registry.all
			subscriptions.each { |subscription| manager.subscribe_all(subscription.id, subscription.live_filters) }
		end

		def open_seed_connections
			NostrClient.configuration.relays.each { |url| manager.add_connection(url) }
		end

		def schedule_reconcile
			NostrClient.reactor.schedule { EM.add_periodic_timer(reconcile_interval) { reconcile } }
		end

		# Two failure-isolated steps: a reconcile error must NOT skip the status snapshot (the web UI would go
		# stale), and neither may raise out and kill the periodic timer.
		def reconcile
			Rails.application.executor.wrap do
				reconcile_relays
				write_status_snapshot
			end
		end

		def reconcile_relays
			Reconcile.call
		rescue StandardError => e
			Rails.logger.error("[Relays::Sync] reconcile error: #{e.class}: #{e.message}")
		end

		# Hand the live connection states to the web UI (Solid Cache snapshot).
		def write_status_snapshot
			StatusSnapshot.new.write(manager.status)
		rescue StandardError => e
			Rails.logger.error("[Relays::Sync] status snapshot error: #{e.class}: #{e.message}")
		end
	end
end
