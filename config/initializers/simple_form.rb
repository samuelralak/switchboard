# frozen_string_literal: true

# Simple Form configured for Tailwind CSS v4.
#
# These wrappers style inputs with explicit utility classes (no @tailwindcss/forms
# plugin), which keeps the asset build Node-free. Checkboxes/radios use accent-*
# so they tint correctly without the forms plugin. For richer controls (custom
# selects, comboboxes, dialogs) reach for Tailwind Plus Elements in the markup.

# Let Simple Form own error styling via :error_class. Without this, Rails wraps
# every invalid field in <div class="field_with_errors">, which breaks layouts.
ActionView::Base.field_error_proc = proc { |html_tag, _instance| html_tag }

SimpleForm.setup do |config|
  # Shared utility class strings, defined once and reused across wrappers.
  label_class = "block text-sm font-medium text-gray-900"
  input_class = "mt-1 block w-full rounded-md border border-gray-300 bg-white px-3 py-2 " \
                "text-sm text-gray-900 placeholder:text-gray-400 shadow-xs " \
                "focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 " \
                "disabled:cursor-not-allowed disabled:bg-gray-50 disabled:text-gray-500"
  input_error_class = "border-red-400 text-red-900 placeholder:text-red-300 " \
                      "focus:border-red-500 focus:ring-red-500"
  input_valid_class = "border-green-500"
  hint_class  = "mt-1 text-sm text-gray-500"
  error_class = "mt-1 text-sm text-red-600"

  # Default wrapper: text-like inputs (string, email, password, number, text, select, ...).
  config.wrappers :tailwind, class: "mb-5" do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :minlength
    b.optional :pattern
    b.optional :min_max
    b.optional :readonly

    b.use :label, class: label_class
    b.use :input, class: input_class, error_class: input_error_class, valid_class: input_valid_class
    b.use :error, wrap_with: { tag: :p, class: error_class }
    b.use :hint,  wrap_with: { tag: :p, class: hint_class }
  end

  # Checkboxes and single boolean inputs: checkbox beside its label.
  config.wrappers :tailwind_boolean, class: "mb-5" do |b|
    b.use :html5
    b.optional :readonly

    b.wrapper :boolean_row, tag: "div", class: "flex items-center gap-x-2" do |ba|
      ba.use :input, class: "h-4 w-4 rounded border-gray-300 accent-indigo-600 focus:ring-indigo-500",
                     error_class: "border-red-400"
      ba.use :label, class: label_class
    end
    b.use :error, wrap_with: { tag: :p, class: error_class }
    b.use :hint,  wrap_with: { tag: :p, class: hint_class }
  end

  # File inputs: styled upload button via the file: modifier.
  config.wrappers :tailwind_file, class: "mb-5" do |b|
    b.use :html5
    b.use :label, class: label_class
    b.use :input,
          class: "mt-1 block w-full text-sm text-gray-700 file:mr-4 file:rounded-md file:border-0 " \
                 "file:bg-indigo-50 file:px-4 file:py-2 file:text-sm file:font-semibold " \
                 "file:text-indigo-700 hover:file:bg-indigo-100",
          error_class: "text-red-700"
    b.use :error, wrap_with: { tag: :p, class: error_class }
    b.use :hint,  wrap_with: { tag: :p, class: hint_class }
  end

  config.default_wrapper = :tailwind
  config.wrapper_mappings = {
    boolean: :tailwind_boolean,
    file: :tailwind_file
  }

  # inline => checkbox + label as siblings (matches the :tailwind_boolean flex row).
  config.boolean_style = :inline
  config.boolean_label_class = nil

  # Submit/action buttons.
  config.button_class = "inline-flex justify-center rounded-md bg-indigo-600 px-4 py-2 text-sm " \
                        "font-semibold text-white shadow-xs hover:bg-indigo-500 focus:outline-none " \
                        "focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 " \
                        "disabled:cursor-not-allowed disabled:opacity-50"

  # error_notification helper (form-level error banner).
  config.error_notification_tag = :div
  config.error_notification_class = "mb-4 rounded-md bg-red-50 p-4 text-sm font-medium text-red-700"

  # Error/valid classes for the bare f.input_field helper.
  config.input_field_error_class = input_error_class
  config.input_field_valid_class = input_valid_class

  # Rely on server-side validations rather than native browser popups.
  config.browser_validations = false
end
