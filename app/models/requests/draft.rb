# frozen_string_literal: true

module Requests
	# Builds an in-memory Requests::OpenRequest from composer form params, for the on-demand preview the
	# request composer renders in a drawer. Mirrors the kind-30402 tag shape the browser publisher signs
	# (NIP-99 + the request marker), so the preview renders the very component the board uses. It is
	# render-equivalent, NOT byte-equivalent: the canonical wire format is request_publish.js
	# buildRequestEvent. Deliberate divergences for a preview (none reach the board):
	#   - d: a literal "preview" placeholder; the real d-tag is random (or carried on edit), unknowable here.
	#   - no created_at / id / signature: this is an unsaved, unsigned Event.
	#   - no status / published_at tags: visibility/carry metadata the preview does not render.
	# The tag head, image machinery, param lookup, title, and the preview factory live in Events::Draftable;
	# this keeps only the request's divergent body tags (the fixed budget, the delivery + claim windows).
	# Pure: builds an unsaved Event, never touches the database.
	class Draft
		include Events::Draftable

		# A Requests::OpenRequest over an unsaved kind-30402 Event, attributed to the previewing consumer.
		def self.open_request(params, pubkey: nil) = preview(params, pubkey:)

		def self.presenter_class = Requests::OpenRequest

		private

		def body_tags_order
			%i[capability_tag budget_tag delivery_window_tag claim_window_tag]
		end

		# The funded budget reuses NIP-99's price tag; a bounty is a single fixed amount (brief §10.2: one
		# budget, no bidding), so there is NEVER a 4th frequency element. Kept distinct from the listing's
		# Catalog::Draft#price_tag on purpose, so a recurring frequency can never leak onto a budget.
		def budget_tag
			budget = field(:budget)
			[ "price", budget.to_s, "sat" ] if budget.present?
		end

		# Both windows are emitted unconditionally (no fulfillment gate, unlike the listing).
		def delivery_window_tag = window_tag("delivery_window", :delivery_value, :delivery_unit)
		def claim_window_tag = window_tag("claim_window", :claim_value, :claim_unit)

		def window_tag(name, value_key, unit_key)
			value = field(value_key)
			return if value.blank?

			[ name, window_suffix(value, field(unit_key)) ]
		end
	end
end
