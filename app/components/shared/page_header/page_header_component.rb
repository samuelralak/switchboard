# frozen_string_literal: true

module Shared
	module PageHeader
		# The standard heading block at the top of a page: an optional copper eyebrow,
		# a required display title, and an optional muted subtitle. The spacing controls
		# the wrapper element and its bottom margin:
		#   :lg  <header class="mb-9">  (default, top-of-page sections)
		#   :md  <div class="mb-6">     (tighter, in-panel sub-sections)
		class PageHeaderComponent < ApplicationComponent
			# An optional top-right action (a primary CTA on an index/management page); when absent the header
			# renders title-only, exactly as before.
			renders_one :action

			SPACINGS = {
				lg: { tag: :header, margin: "mb-9" },
				md: { tag: :div, margin: "mb-6" }
			}.freeze

			attr_reader :eyebrow, :title, :subtitle

			def initialize(title:, eyebrow: nil, subtitle: nil, spacing: :lg)
				@title = title
				@eyebrow = eyebrow
				@subtitle = subtitle
				@spacing = SPACINGS.key?(spacing.to_s.to_sym) ? spacing.to_s.to_sym : :lg
			end

			def wrapper_tag = SPACINGS.fetch(@spacing)[:tag]
			def wrapper_class = SPACINGS.fetch(@spacing)[:margin]
		end
	end
end
