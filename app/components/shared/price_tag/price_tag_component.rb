# frozen_string_literal: true

module Shared
	module PriceTag
		# Monospaced amount with a faint unit suffix. The size sets the figure and
		# suffix scale; the tone sets the figure color:
		#   :sm     text-base (default)
		#   :lg     text-2xl
		#   :inline text-sm, smaller suffix
		#   :copper text-copper (default)
		#   :ink    text-ink
		# `amount:` is an Integer and renders with thousands delimiters.
		class PriceTagComponent < ApplicationComponent
			SIZES = {
				sm: "text-base",
				lg: "text-2xl",
				inline: "text-sm"
			}.freeze

			TONES = {
				copper: "text-copper",
				ink: "text-ink"
			}.freeze

			attr_reader :suffix

			def initialize(amount:, size: :sm, tone: :copper, suffix: "sat")
				@amount = amount
				@size = SIZES.key?(size.to_s.to_sym) ? size.to_s.to_sym : :sm
				@tone = TONES.key?(tone.to_s.to_sym) ? tone.to_s.to_sym : :copper
				@suffix = suffix
			end

			def size_text = SIZES.fetch(@size)
			def tone_class = TONES.fetch(@tone)
			def amount_delimited = helpers.number_with_delimiter(@amount)

			def suffix_cls
				@size == :inline ? "text-ink-faint text-xs" : "text-ink-faint text-sm font-normal"
			end
		end
	end
end
