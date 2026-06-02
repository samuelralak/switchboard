# frozen_string_literal: true

# Simple Form skinned to the Switchboard prototype (dark canvas, copper accent,
# JetBrains Mono labels). Text inputs, textareas, and selects share one field
# style; numeric/URL fields add font-mono; the invalid state forces a
# lamp-fault border, all matching the prototype. No @tailwindcss/forms plugin,
# so the asset build stays Node-free.

# Let Simple Form own error styling via :error_class instead of Rails' default
# field_with_errors wrapper, which injects a div that breaks the layout.
ActionView::Base.field_error_proc = proc { |html_tag, _instance| html_tag }

SimpleForm.setup do |config|
  focus = "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-copper-bright " \
          "focus-visible:ring-offset-2 focus-visible:ring-offset-canvas"

  # The prototype's INPUT constant: text inputs, textareas, and selects share it.
  field = "w-full rounded-lg border border-border bg-inset px-3.5 py-2.5 text-sm text-ink " \
          "placeholder:text-ink-faint transition-colors hover:border-border-strong #{focus}"
  field_mono = "#{field} font-mono" # numeric / URL / identifier fields

  # Field label: mono + uppercase, with the required/optional marker pushed to
  # the right (the marker text/colour comes from config.label_text below).
  label_class = "flex items-baseline justify-between gap-2 font-mono text-xs uppercase " \
                "tracking-wider text-ink-muted mb-2"

  error_input = "!border-lamp-fault"
  error_text  = "mt-1.5 font-mono text-xs text-lamp-fault"
  hint_text   = "mt-1.5 font-mono text-xs text-ink-faint"

  # Default wrapper: string / email / password / text / select.
  config.wrappers :switchboard, class: "mb-5" do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :minlength
    b.optional :pattern
    b.optional :min_max
    b.optional :readonly

    b.use :label, class: label_class
    b.use :input, class: field, error_class: error_input
    b.use :error, wrap_with: { tag: :p, class: error_text }
    b.use :hint,  wrap_with: { tag: :p, class: hint_text }
  end

  # Numeric and URL fields: identical, plus font-mono (machine values).
  config.wrappers :switchboard_mono, class: "mb-5" do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :minlength
    b.optional :pattern
    b.optional :min_max
    b.optional :readonly

    b.use :label, class: label_class
    b.use :input, class: field_mono, error_class: error_input
    b.use :error, wrap_with: { tag: :p, class: error_text }
    b.use :hint,  wrap_with: { tag: :p, class: hint_text }
  end

  # Checkbox / boolean: copper-accented control beside an inline label.
  config.wrappers :switchboard_boolean, class: "mb-5" do |b|
    b.use :html5
    b.optional :readonly

    b.wrapper :boolean_row, tag: "div", class: "flex items-center gap-x-2.5" do |ba|
      ba.use :input, class: "size-4 accent-copper #{focus}", error_class: error_input
      ba.use :label, class: "text-sm text-ink-secondary"
    end
    b.use :error, wrap_with: { tag: :p, class: error_text }
    b.use :hint,  wrap_with: { tag: :p, class: hint_text }
  end

  # File input: the prototype has none, so this extrapolates the system with a
  # copper upload button on the shared field shell.
  config.wrappers :switchboard_file, class: "mb-5" do |b|
    b.use :html5
    b.use :label, class: label_class
    b.use :input,
          class: "w-full text-sm text-ink-muted file:mr-4 file:rounded-md file:border-0 " \
                 "file:bg-copper/10 file:px-4 file:py-2 file:text-sm file:font-medium " \
                 "file:text-copper hover:file:bg-copper/20 #{focus}",
          error_class: error_input
    b.use :error, wrap_with: { tag: :p, class: error_text }
    b.use :hint,  wrap_with: { tag: :p, class: hint_text }
  end

  config.default_wrapper = :switchboard
  config.wrapper_mappings = {
    boolean: :switchboard_boolean,
    file: :switchboard_file,
    integer: :switchboard_mono,
    decimal: :switchboard_mono,
    float: :switchboard_mono,
    url: :switchboard_mono
  }

  # inline => checkbox + label as siblings (matches the boolean_row above).
  config.boolean_style = :inline
  config.boolean_label_class = nil

  # Right-aligned "required" / "optional" marker (copper / faint, normal-case),
  # matching the prototype. Pairs with the flex label_class above.
  config.label_text = lambda do |label, required, _explicit_label|
    helpers = ActionController::Base.helpers
    tone = required.present? ? "text-copper" : "text-ink-faint"
    marker = helpers.content_tag(:span, required.present? ? "required" : "optional",
                                 class: "#{tone} normal-case tracking-normal")
    helpers.safe_join([ label, marker ])
  end

  # Primary action button = the prototype's BTN_PRIMARY.
  config.button_class = "inline-flex items-center justify-center gap-2 rounded-lg font-medium " \
                        "transition-colors #{focus} disabled:opacity-40 disabled:pointer-events-none " \
                        "h-10 px-4 bg-copper text-canvas hover:bg-copper-bright active:translate-y-px"

  # Form-level error banner = the prototype's error banner (without the icon).
  config.error_notification_tag = :div
  config.error_notification_class = "rounded-xl border border-lamp-fault/40 bg-lamp-fault/5 " \
                                    "px-3.5 py-2.5 mb-4 text-sm text-ink-secondary"

  # Error class for the bare f.input_field helper.
  config.input_field_error_class = error_input

  # Rely on server-side validations rather than native browser popups.
  config.browser_validations = false
end
