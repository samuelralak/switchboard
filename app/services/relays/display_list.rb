# frozen_string_literal: true

module Relays
	# The relays shown in the UI for a viewer: the viewer's own NIP-65 relays with their advertised read/write
	# roles, decorated with live/settled status from the cross-process StatusSnapshot. This is "your relays",
	# so it shows everything the user advertises -- NOT just the capped subset the catalog ingest happens to
	# dial (a relay the ingest does not dial simply reads as settled). A signed-out viewer (or one with no
	# list yet) falls back to the platform seeds as general-purpose defaults. Best-effort: a relay absent from
	# the snapshot reads as settled. Returns [{ host:, status:, read:, write: }] (host is the ws(s) url minus
	# the scheme) for the sidebar + settings + manage-dialog views.
	class DisplayList < BaseService
		option :user
		option :snapshot, default: -> { StatusSnapshot.new }

		def call
			statuses = snapshot.read
			relay_rows.map do |url, read, write|
				{ host: host_for(url), status: status_for(url, statuses), read:, write: }
			end
		end

		private

		def relay_rows
			return seed_rows unless user

			user.user_relays.order(:url).pluck(:url, :read, :write).presence || seed_rows
		end

		# Seeds are general-purpose platform defaults: read + write.
		def seed_rows
			NostrClient.configuration.relays.map { |url| [ url, true, true ] }
		end

		# Display label: the url minus the ws(s):// scheme, so two endpoints on the same host (e.g. a
		# .../inbox path, or a non-default port) stay distinct instead of collapsing to a duplicate hostname.
		def host_for(url) = url.sub(%r{\Awss?://}, "")

		def status_for(url, statuses) = statuses[url] == "connected" ? :live : :settled
	end
end
