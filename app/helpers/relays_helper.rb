# frozen_string_literal: true

# The relay set shown in the sidebar group, the manage modal, and the settings page: the signed-in user's
# own NIP-65 write relays unioned with our default seeds, lit with live connection status. Built by
# Relays::DisplayList (seeds + user relays + the cross-process status snapshot).
module RelaysHelper
	SIDEBAR_RELAY_CAP = 4

	# Current.user (not current_user) so it resolves the same in a ViewComponent, a plain view, and a
	# controller; nil for a signed-out viewer, which DisplayList renders as just the seeds.
	def display_relays = Relays::DisplayList.call(user: Current.user)

	# The relays the signed-in viewer publishes their own events to: seeds unioned with their NIP-65 write
	# relays. For the in-view status-toggle controllers (my-listings / my-requests) that re-broadcast a flip.
	def publish_relays = Relays::PublishSet.call(user: Current.user)

	# Live/settled lamp class for a relay's connection status, matching the catalog status dots.
	def relay_status_class(status)
		status == :live ? "bg-lamp-live" : "bg-lamp-settled"
	end

	# The relay's NIP-65 role label: outbox (write), inbox (read), or both.
	def relay_role(relay)
		return "read/write" if relay[:read] && relay[:write]

		relay[:write] ? "write" : "read"
	end
end
