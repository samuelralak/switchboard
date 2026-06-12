# frozen_string_literal: true

module Settings
	module Ui
		# Render state for the settings surfaces. `profile` assembles the non-custodial profile editor's
		# context: the user, the publish identity + relays the browser signs and broadcasts to, and the raw
		# winning kind-0 the browser merges edits onto. `relays` assembles the relay-list editor's context: the
		# user (the form prefills its rows from the projection) + the publish relays. Mirrors Catalog::Ui::State
		# / Requests::Ui::State.
		class State
			Profile   = Data.define(:user, :pubkey, :publish_relays, :metadata_event)
			RelayList = Data.define(:user, :pubkey, :publish_relays)

			def self.profile(user:)
				Profile.new(
					user:,
					pubkey: user.pubkey,
					publish_relays: Relays::PublishSet.call(user:),
					metadata_event: Event.of_kind(Events::Kinds::METADATA).by_author(user.pubkey).recent.first
				)
			end

			def self.relays(user:)
				RelayList.new(user:, pubkey: user.pubkey, publish_relays: Relays::PublishSet.call(user:))
			end
		end
	end
end
