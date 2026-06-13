# frozen_string_literal: true

module Profiles
	module Ui
		# Render state for the public profile = a user's two-sided marketplace presence: the resolved identity,
		# whether the viewer owns it, and the two collections (services offered + open requests posted). A pure
		# builder: the npub decode, the 404, and the lazy kind-0 fetch live in Profiles::Resolve, so this mirrors
		# the side-effect-free Settings::Ui::State / Catalog::Ui::State factories.
		class State
			Portfolio = Data.define(:pubkey, :user, :owner, :listings, :requests) do
				def owner? = owner
				def projected? = user.present?

				# The live subset of each collection (all a visitor is ever shown).
				def active_listings = listings.select(&:active?)
				def open_requests = requests.select(&:open?)

				# What this viewer sees in each section: the owner manages everything (incl. inactive listings /
				# withdrawn requests), a visitor sees only the live ones. The section body, the heading count pill,
				# and the reputation-strip count all read the SAME role-scoped collection, so they never disagree and
				# a visitor never sees the owner's draft/withdrawn counts.
				def services_shown = owner ? listings : active_listings
				def requests_shown = owner ? requests : open_requests
				def service_count = services_shown.size
				def request_count = requests_shown.size

				# Role-scoped "nothing to show on either side": one unified empty profile, not two stacked voids.
				def empty? = services_shown.empty? && requests_shown.empty?

				# The canonical npub, for the not-yet-projected placeholder (no user to read it off yet).
				def npub = Nostr::Bech32.npub_encode(pubkey)
			end

			# Builds the render state from an already-resolved identity (Profiles::Resolve owns the npub decode,
			# the 404, and the lazy fetch). Pure construction, like the sibling Ui::State factories.
			def self.portfolio(pubkey:, user:, owner:)
				Portfolio.new(
					pubkey:,
					user:,
					owner:,
					listings: user ? Catalog::ProviderListings.call(pubkey:) : [],
					requests: user ? Requests::AuthoredRequests.call(pubkey:) : []
				)
			end
		end
	end
end
