# frozen_string_literal: true

# The relay set shown in the sidebar group, the manage modal, and the settings page. Mock data and
# status for now (a prototype shell); once NIP-65 / kind-10050 ingestion lands this becomes the
# signed-in user's own relays with live connection status.
module RelaysHelper
	SIDEBAR_RELAY_CAP = 4

	def display_relays
		[
			{ host: "relay.damus.io",   status: :settled },
			{ host: "nos.lol",          status: :settled },
			{ host: "relay.primal.net", status: :settled },
			{ host: "nostr.band",       status: :live },
			{ host: "auth.nostr1.com",  status: :live }
		]
	end

	# Live/settled lamp class for a relay's connection status, matching the catalog status dots.
	def relay_status_class(status)
		status == :live ? "bg-lamp-live" : "bg-lamp-settled"
	end
end
