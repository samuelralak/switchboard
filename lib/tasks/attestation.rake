# frozen_string_literal: true

namespace :attestation do
	desc "Attest existing conforming listings/requests (one-time, idempotent) so the verified default does not hide them"
	task backfill: :environment do
		unless Attestation::Policy.issuing?
			abort "[attestation:backfill] issuing is off (no policy or signing key); nothing to do."
		end

		if NostrClient.configuration.dm_relays.empty?
			abort "[attestation:backfill] no publish relays configured; cannot broadcast labels."
		end

		# A rake process opens no relay connections, so boot publishing here and tear it down after.
		NostrClient.boot_publishing!
		begin
			result = Attestation::Backfill.call
			summary = "Attested #{result[:attested]} listing(s)/request(s)"
			summary += ", #{result[:failed]} skipped on error (see log)" if result[:failed].positive?
			puts "#{summary}."
		ensure
			NostrClient.stop
		end
	end
end
