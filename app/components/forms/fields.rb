# frozen_string_literal: true

module Forms
	# The shared authoring-form field standards: the input/label/focus class strings + the field helpers, so
	# every form (studio, request, order-flow) renders identical fields from one source of truth. Include into
	# a ViewComponent; the constants resolve in the template via the ancestor chain.
	module Fields
		FOCUS = "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-copper-bright " \
						"focus-visible:ring-offset-2 focus-visible:ring-offset-canvas"

		INPUT = "w-full rounded-lg border border-border bg-inset px-3.5 py-2.5 text-sm text-ink " \
						"placeholder:text-ink-faint transition-colors hover:border-border-strong " \
						"focus-visible:border-copper-dim #{FOCUS}".freeze

		# Eyebrow-style field label: sans (font-mono is reserved for data values, never labels).
		LABEL = "block text-xs font-medium uppercase tracking-wider text-ink-muted mb-2"

		# Data inputs (capability, price, machine names) get mono; prose inputs stay sans.
		def input_class(data: false) = data ? "#{INPUT} font-mono" : INPUT

		# A copper asterisk marking a required field (decorative; the label text carries the meaning).
		def req = tag.span("*", class: "text-copper", aria: { hidden: "true" })

		def required_tag = section_tag("Required", "bg-copper/10 text-copper")
		def optional_tag = section_tag("Optional", "border border-border text-ink-faint")

		private

		def section_tag(text, tone)
			classes = "shrink-0 rounded-full px-2 py-0.5 text-[0.625rem] font-medium uppercase tracking-wider #{tone}"
			tag.span(text, class: classes)
		end
	end
end
