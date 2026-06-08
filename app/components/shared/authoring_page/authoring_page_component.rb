# frozen_string_literal: true

module Shared
	module AuthoringPage
		# The shared skeleton for the two single-column authoring pages (the provider-studio service listing
		# and the open request): the Stimulus-wired wrapper, the page header, the form-then-rail grid, and the
		# section nav rail. The pages differ in their Stimulus controller, the value attributes it reads, and
		# the divergent content, so the form, the action buttons, the success receipt, and the preview drawer
		# come in as slots; the controller name, its values, the rail sections, and the header text are passed.
		class AuthoringPageComponent < ApplicationComponent
			renders_one :form
			renders_one :actions
			renders_one :receipt
			renders_one :preview

			# stimulus is named to avoid shadowing ViewComponent::Base#controller (the request's controller,
			# which helpers depend on).
			attr_reader :stimulus, :values, :sections, :heading, :subtitle

			# stimulus: the Stimulus identifier ("studio" / "request-form"). values: the data-<stimulus>-<key>-
			# value attributes as an ordered { "key" => value } hash, rendered verbatim so the publish controller
			# reads exactly the names it expects. sections: the form's SECTIONS (the rail).
			def initialize(stimulus:, values:, sections:, heading:, subtitle:)
				@stimulus = stimulus
				@values = values
				@sections = sections
				@heading = heading
				@subtitle = subtitle
			end
		end
	end
end
