# frozen_string_literal: true

module Settings
	module Shell
		# The settings chrome shared by every settings sub-page: a left section rail (Profile / Relays /
		# Signer·soon / Notifications·soon) beside the active page's content. Each sub-page renders this with its
		# own `active` key and yields the main content. The rail items are real navigation (one route per
		# section), so the active one is highlighted by route, not by scroll position.
		class ShellComponent < ApplicationComponent
			def initialize(active:)
				@active = active
			end

			def items
				[
					{ key: :profile, label: "Profile", icon: "hgi-user-circle", path: helpers.settings_profile_path },
					{ key: :relays, label: "Relays", icon: "hgi-radar-01", path: helpers.settings_relays_path },
					{ key: :signer, label: "Signer", icon: "hgi-square-lock-02", soon: true },
					{ key: :notifications, label: "Notifications", icon: "hgi-notification-02", soon: true }
				]
			end

			def active?(key) = key == @active
		end
	end
end
