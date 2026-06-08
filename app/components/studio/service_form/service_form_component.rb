# frozen_string_literal: true

module Studio
	module ServiceForm
		# The provider-studio authoring form (single column beside the section rail): details, images, the
		# delivery/fulfillment mode, and the dynamic buyer-input schema. Prefills from a Catalog::Listing
		# draft so one component serves both `new` (empty) and edit. The Stimulus `studio` controller wires
		# row repeat, the fiat hint, section scroll-spy + progress, the on-demand buyer preview, strict
		# client validation, and the non-custodial sign + broadcast on publish.
		class ServiceFormComponent < ApplicationComponent
			include Forms::Fields # FOCUS/INPUT/LABEL + input_class/req/required_tag/optional_tag

			# A pricing-basis toggle segment ("Per request" / "Per hour"), selected via aria-pressed.
			PRICE_BASIS = "inline-flex items-center h-7 px-2.5 rounded-md text-xs font-medium text-ink-muted " \
							"transition-colors hover:text-ink aria-pressed:bg-surface-2 aria-pressed:text-ink #{FOCUS}".freeze

			# The authoring sections, in order. Shared with the rail (_form_page) so the nav and the form
			# headers stay in lockstep. `required` drives both the Required/Optional tag and the rail's
			# progress dot.
			SECTIONS = [
				{ id: "details", title: "Details", required: true },
				{ id: "inputs", title: "Buyer inputs", required: false },
				{ id: "images", title: "Images", required: false },
				{ id: "delivery", title: "Delivery", required: true }
			].freeze

			attr_reader :listing, :pubkey, :d_tag

			def initialize(listing:, pubkey: nil, d_tag: nil)
				@listing = listing
				@pubkey = pubkey
				@d_tag = d_tag # present on edit -> the publisher re-publishes under this coordinate (supersede)
			end

			# Existing listing images as { url:, m:, x:, dim: } hashes (cover first), prerendered for edit.
			def existing_images
				listing.images.map { |url| listing.image_meta(url).merge(url:) }
			end

			# Manual is the only shippable mode for now; automated is shown as coming-soon (see the form).
			def mode = listing.fulfillment.presence || "manual"
			def automated? = mode == "automated"

			# Pricing basis: per-request (no NIP-99 frequency) vs per-hour ("hour"). Prefilled on edit.
			delegate :price_frequency, :per_hour?, to: :listing

			def field_types = Types::InputFieldType.values

			# Manual delivery window split back into value + unit for prefill ("24h" -> 24, "hours").
			def delivery_value = listing.delivery_window.to_s[/\A(\d+)/, 1]
			def delivery_unit = listing.delivery_window.to_s.end_with?("d") ? "days" : "hours"
		end
	end
end
