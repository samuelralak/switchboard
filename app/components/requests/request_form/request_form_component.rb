# frozen_string_literal: true

module Requests
	module RequestForm
		# The open-request authoring form (single column beside the section rail): the need, the funded budget,
		# the timing windows, and the funded-bounty/escrow note. Prefills from a Requests::OpenRequest draft so
		# one component serves both `new` (empty) and a future edit. The Stimulus `request-form` controller
		# wires the fiat hint, section scroll-spy + progress, the on-demand preview, strict client validation,
		# and the non-custodial sign + broadcast on publish. Mirrors Studio::ServiceForm on the demand side.
		class RequestFormComponent < ApplicationComponent
			include Forms::Fields # FOCUS/INPUT/LABEL + input_class/req/required_tag/optional_tag

			# The authoring sections, in order. Shared with the rail (_form_page) so the nav and the form headers
			# stay in lockstep. `required` drives both the Required/Optional tag and the rail's progress dot.
			# Funding is informational (escrow + fee come with payments), so it is optional.
			SECTIONS = [
				{ id: "details", title: "Details", required: true },
				{ id: "images", title: "Images", required: false },
				{ id: "budget", title: "Budget", required: true },
				{ id: "timing", title: "Timing", required: true },
				{ id: "funding", title: "Funding", required: false }
			].freeze

			attr_reader :request, :pubkey, :d_tag

			def initialize(request:, pubkey: nil, d_tag: nil)
				@request = request
				@pubkey = pubkey
				@d_tag = d_tag # present on edit -> the publisher re-publishes under this coordinate (supersede)
			end

			# Existing request images as { url:, m:, x:, dim: } hashes (cover first), prerendered for edit.
			def existing_images
				request.images.map { |url| request.image_meta(url).merge(url:) }
			end

			# The title, blank when it is the placeholder default (so the input shows its placeholder on new).
			def title_value = request.title == Requests::OpenRequest::DEFAULT_TITLE ? nil : request.title

			# Windows split back into value + unit for prefill. The value is left blank on a new request (a
			# placeholder hints 24 / 3) so the rail's progress dot reflects what the user enters, not a default;
			# the unit selects default to hours (delivery) and days (claim), the common cases.
			def delivery_value = request.delivery_window.to_s[/\A(\d+)/, 1]
			def delivery_unit = request.delivery_window.to_s.end_with?("d") ? "days" : "hours"
			def claim_value = request.claim_window.to_s[/\A(\d+)/, 1]
			def claim_unit = request.claim_window.to_s.end_with?("h") ? "hours" : "days"
		end
	end
end
