require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module AmEvent
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    # NOTE: Keeping Rails 7.0 defaults to avoid SQL reserved word quoting requirements.
    # Rails 8.0 requires quoting columns named 'order' and 'name' which would need
    # extensive codebase changes. Consider renaming these columns in the future.
    config.load_defaults 7.0
    config.active_support.to_time_preserves_timezone = :zone

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    
    # Add lib directory to autoload paths
    config.autoload_paths << Rails.root.join("lib")
  end
end
