require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Switchboard
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # ViewComponent (https://viewcomponent.org): components inherit
    # ApplicationComponent and live in a folder per component (namespaced), e.g.
    # app/components/sidebar/sidebar_component.rb with an adjacent template.
    # Previews render in the dark component_preview layout and are served at
    # /rails/view_components in development and test.
    config.view_component.component_parent_class = "ApplicationComponent"
    config.view_component.generate.sidecar = false
    config.view_component.generate.preview = true
    config.view_component.previews.default_layout = "component_preview"

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
