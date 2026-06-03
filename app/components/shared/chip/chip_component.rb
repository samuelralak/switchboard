# frozen_string_literal: true

module Shared
	module Chip
		# Inline status pill of a colored dot plus a short mono label. The tone sets
		# the text and dot color:
		#   :copper   in-progress states
		#   :live     active / open states
		#   :settled  completed / settled states
		#   :fault    failed / expired states
		#   :muted    dim text with a faint dot (default)
		#   :neutral  dim text with a muted dot
		#   :faint    faint text, no dot
		# Label comes from `label:` or the content slot. `dot: false` hides the
		# leading dot; `bordered: true` wraps the chip in a bordered surface.
		class ChipComponent < ApplicationComponent
			TONES = {
				copper: { text: "text-copper", dot: "bg-copper" },
				live: { text: "text-lamp-live", dot: "bg-lamp-live" },
				settled: { text: "text-lamp-settled", dot: "bg-lamp-settled" },
				fault: { text: "text-lamp-fault", dot: "bg-lamp-fault" },
				muted: { text: "text-ink-muted", dot: "bg-ink-faint" },
				neutral: { text: "text-ink-muted", dot: "bg-ink-muted" },
				faint: { text: "text-ink-faint", dot: nil }
			}.freeze

			BORDERED_CLASS = "rounded-md border border-border bg-surface px-2.5 py-1"

			attr_reader :label

			def initialize(tone: :muted, label: nil, dot: true, bordered: false)
				@tone = TONES.key?(tone.to_s.to_sym) ? tone.to_s.to_sym : :muted
				@label = label
				@dot = dot
				@bordered = bordered
			end

			def wrapper_class
				base = "inline-flex items-center gap-2 font-mono text-xs"
				[ base, TONES.fetch(@tone)[:text], (@bordered ? BORDERED_CLASS : nil) ].compact.join(" ")
			end

			def dot_class = TONES.fetch(@tone)[:dot]
			def show_dot? = @dot && !dot_class.nil?
		end
	end
end
