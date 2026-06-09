# frozen_string_literal: true

# Register each domain's relay-ingest Subscription with the central Relays::Registry. The relay subsystem
# (Relays::Sync, in the relay:boot process) reads this once at start to wire the live subscriptions, route
# inbound events, and backfill newly added relays. Adding a consumer (e.g. notes) is one more register line
# here, with no new relay code. Wrapped in to_prepare so the registry survives dev code reloads; the running
# relay:boot process reads the registry only at start, so changing a subscription's filters needs a restart.
Rails.application.config.to_prepare do
	Relays::Registry.instance.register(Catalog::RelaySubscription.call)
end
