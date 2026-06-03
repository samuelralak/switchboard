# frozen_string_literal: true

# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# Tailwind Plus Elements: headless interactive web components (dialog, dropdown,
# tabs, popover, command palette, select, autocomplete, etc.). Vendored in
# vendor/javascript/. Requires a Tailwind Plus license (https://tailwindcss.com/plus).
pin "@tailwindplus/elements", to: "@tailwindplus--elements.js" # @1.0.22
