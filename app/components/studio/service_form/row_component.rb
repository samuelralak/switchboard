# frozen_string_literal: true

module Studio
	module ServiceForm
		# One input-schema row: a machine name (mono data), a human label (sans), a type select, a
		# required toggle, and a remove control. Rendered server-side for existing fields and also inside
		# a <template> the Stimulus controller clones for "Add field", so the markup has one source.
		# `field` is a { name:, label:, type:, required: } hash (string or symbol keys tolerated).
		class RowComponent < ApplicationComponent
			def initialize(field: {})
				@field = (field || {}).symbolize_keys
			end

			def name = @field[:name]
			def label = @field[:label]
			def type = @field[:type].presence || "text"
			def required? = @field[:required] == true
			def field_types = Types::InputFieldType.values
			def input_class = ServiceFormComponent::INPUT
		end
	end
end
