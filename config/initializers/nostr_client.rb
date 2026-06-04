# frozen_string_literal: true

# Bootstrap (seed) relays for the server-side NostrClient, loaded from this app's
# config/relays.yml for the current environment. A signed-in user's own relays
# (NIP-65) are added on top of these at runtime via the Manager, so this is only
# the starting set. Runs in to_prepare so the setting survives code reloading in
# development; the Types::Relays constructor rejects a malformed URL here.
Rails.application.config.to_prepare do
	NostrClient.configure do |config|
		relays = Rails.application.config_for(:relays)
		config.relays = relays.urls
		config.dm_relays = relays.dm_relays || []
		# Answer NIP-42 AUTH with the R_op key, but only once it is provisioned in credentials
		# (so boot and the catalog ingest work fine before the operational key exists).
		config.auth_signer = Operational::Signer.new if Operational::Signer.configured?
	end
rescue StandardError => e
	Rails.logger.warn("[NostrClient] relay configuration skipped: #{e.class}: #{e.message}")
end
