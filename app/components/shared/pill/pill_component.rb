# frozen_string_literal: true

module Shared
	module Pill
		# A small inline status pill with an optional leading dot. The :copper variant
		# (default) is copper-toned; the :surface variant takes its text/dot color from
		# tone (copper/live/settled/fault/muted, default copper). The label is block
		# content or the :label keyword; dot: false hides the dot.
		class PillComponent < ApplicationComponent
			VARIANTS = {
				copper: {
					border: "border-copper-dim", bg: "bg-copper/10", pad: "px-2 py-0.5"
				},
				surface: {
					border: "border-border", bg: "bg-surface", pad: "px-2.5 py-1"
				}
			}.freeze

			TONES = {
				copper: { text: "text-copper", dot: "bg-copper" },
				live: { text: "text-lamp-live", dot: "bg-lamp-live" },
				settled: { text: "text-lamp-settled", dot: "bg-lamp-settled" },
				fault: { text: "text-lamp-fault", dot: "bg-lamp-fault" },
				muted: { text: "text-ink-muted", dot: "bg-ink-muted" }
			}.freeze

			attr_reader :label

			def initialize(variant: :copper, tone: :copper, label: nil, dot: true)
				@variant = VARIANTS.key?(variant.to_s.to_sym) ? variant.to_s.to_sym : :copper
				@tone = TONES.key?(tone.to_s.to_sym) ? tone.to_s.to_sym : :copper
				@label = label
				@dot = dot
			end

			def dot? = @dot

			def border_class = VARIANTS.fetch(@variant)[:border]
			def bg_class = VARIANTS.fetch(@variant)[:bg]
			def pad_class = VARIANTS.fetch(@variant)[:pad]

			def text_class = @variant == :copper ? TONES.fetch(:copper)[:text] : TONES.fetch(@tone)[:text]
			def dot_class = @variant == :copper ? TONES.fetch(:copper)[:dot] : TONES.fetch(@tone)[:dot]
		end
	end
end
