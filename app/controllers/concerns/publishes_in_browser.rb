# frozen_string_literal: true

# Shared plumbing for the non-custodial authoring controllers (studio listings, open requests): the browser
# signs + broadcasts the kind-30402 event, so there is no server create -- only the compose context the form
# needs and the on-demand preview params. Include in a controller and call set_compose_context (before_action
# on new/edit) + preview_params(*its_own_permit_shape) in #preview.
module PublishesInBrowser
	extend ActiveSupport::Concern

	# Carried through an edit (the coordinate + NIP-99 status/timestamps) so a re-publish supersedes cleanly.
	# The Draft ignores them; permitted only so the preview POST logs no unpermitted params.
	CARRY_KEYS = %i[d_tag status published_at created_at].freeze

	private

	def set_compose_context
		@pubkey = current_user.pubkey
		@publish_relays = NostrClient.configuration.relays # the catalog ingest relays; publish there so it is catalogued
		@btc_usd = Pricing::BtcRate.call # nil hides the fiat hint; never blocks the render
	end

	# The in-flight form params for the on-demand preview, minus the framework CSRF token (still verified by
	# Rails before the action; dropped so it does not log as unpermitted). `shape` is the controller's own
	# permit list (its fields, with any nested hash last).
	def preview_params(*shape)
		params.except(:authenticity_token).permit(*CARRY_KEYS, *shape).to_h
	end
end
