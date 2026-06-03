# frozen_string_literal: true

module Layout
	module Breadcrumb
		# Renders a home anchor and a trail of crumbs. Each crumb is { label:, href: };
		# blank-label crumbs are dropped, the last crumb is the current page (plain text
		# with aria-current), and earlier crumbs link when they carry an href.
		class BreadcrumbComponent < ApplicationComponent
			def initialize(crumbs: [])
				@crumbs = Array(crumbs).select { |crumb| crumb[:label].present? }
			end

			attr_reader :crumbs

			def home_path
				helpers.root_path
			rescue StandardError
				"/"
			end

			# True when the crumb at index is not the last and carries an href.
			def link?(index)
				index < crumbs.length - 1 && crumbs[index][:href].present?
			end

			def current?(index) = index == crumbs.length - 1
		end
	end
end
