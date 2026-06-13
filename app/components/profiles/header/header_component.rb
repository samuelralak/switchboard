# frozen_string_literal: true

module Profiles
	module Header
		# The public identity block at the top of a profile: a banner with an overlapping avatar (identicon
		# fallback), then the kind-0 identity (display name, npub, verified NIP-05, lightning address, website,
		# bio). Read-only -- the owner edits via the kind-0 editor (Settings::ProfileForm). Mono stays for data
		# (npub, lightning); sans for the name and prose.
		class HeaderComponent < ApplicationComponent
			attr_reader :user

			def initialize(user:)
				@user = user
			end

			def short_npub = user.npub.truncate(24, omission: "…")

			# Only an http(s) website becomes a link (a kind-0 field could carry a javascript:/data: url).
			def website
				url = user.website.to_s

				url if url.match?(%r{\Ahttps?://}i)
			end

			# The website without its scheme / trailing slash, for the link label.
			def website_label = website&.sub(%r{\Ahttps?://}i, "")&.delete_suffix("/")
		end
	end
end
