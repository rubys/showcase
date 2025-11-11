require "active_support/core_ext/integer/time"
require_relative "../../lib/json_logger" if ENV["RAILS_LOG_JSON"].present?

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.cache_classes = true

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both threaded web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # TurboCable broadcast URL configuration
  # When running on the index/admin server, broadcasts should go to Navigator's port (9999)
  # This ensures background jobs can broadcast progress updates
  ENV['TURBO_CABLE_BROADCAST_URL'] ||= 'http://localhost:9999/_broadcast' if ENV['RAILS_APP_OWNER'] == 'index'

  # Configure host authorization for rubymini admin server
  # Allow rubix.intertwingly.net as the primary host, plus rubymini for internal access
  # This applies to all tenants running on rubymini, not just index
  require 'socket'
  if Socket.gethostname == 'rubymini'
    config.hosts << 'rubix.intertwingly.net'
    config.hosts << /rubymini(:\d+)?/
    # Allow Fly.io and Hetzner hosts that reverse proxy to rubymini
    config.hosts << 'smooth.fly.dev'
    config.hosts << 'hetzner.intertwingly.net'
    config.hosts << 'showcase.party'
    # Allow cross-origin requests from Fly.io and Hetzner for CSRF protection
    config.action_controller.forgery_protection_origin_check = false
    # Set the default URL host for URL generation
    config.action_controller.default_url_options = { host: 'rubix.intertwingly.net', protocol: 'https' }
  end

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local       = false
  config.action_controller.perform_caching = true

  # Ensures that a master key has been made available in either ENV["RAILS_MASTER_KEY"]
  # or in config/master.key. This key is used to decrypt credentials (and other encrypted files).
  # config.require_master_key = true

  # Disable serving static files from the `/public` folder by default since
  # Apache or NGINX already handles this.
  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?

  # Compress CSS using a preprocessor.
  # config.assets.css_compressor = :sass

  # Do not fallback to assets pipeline if a precompiled asset is missed.
  config.assets.compile = false

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = "X-Sendfile" # for Apache
  # config.action_dispatch.x_sendfile_header = "X-Accel-Redirect" # for NGINX

  # Set storage location for uploaded files based on environment
  if ENV["RAILS_APP_OWNER"] == "Demo"
    config.active_storage.service = :local
  # elsif ENV["BUCKET_NAME"]
  #   config.active_storage.service = :tigris
  else
    config.active_storage.service = :local
  end

  # Mount Action Cable outside main process or domain.
  if ENV['RAILS_APP_SCOPE'].present?
    config.action_cable.mount_path = "/#{ENV['RAILS_APP_SCOPE']}/cable"
  end

  if ENV['RAILS_PROXY_HOST'].present?
    config.action_cable.allowed_request_origins = [
      'https://' + ENV['RAILS_PROXY_HOST'].chomp('/')
    ]
  end

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  if ENV['RAILS_RELATIVE_URL_ROOT']
    config.force_ssl = true

    # enable direct access within the LAN
    config.ssl_options = { redirect: { exclude: -> request { 
      request.headers['X-Forwarded-Ssl'] != 'on'
    } } }
  end

  # Include generic and useful information about system operation, but avoid logging too much
  # information to avoid inadvertent exposure of personally identifiable information (PII).
  config.log_level = :debug

  # Prepend all log lines with the following tags.
  config.log_tags = [ :request_id ]

  # Use a different cache store in production.
  # config.cache_store = :mem_cache_store

  # Use a real queuing backend for Active Job (and separate queues per environment).
  # config.active_job.queue_adapter     = :resque
  # config.active_job.queue_name_prefix = "am_event_production"

  config.action_mailer.perform_caching = false

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Use default logging formatter so that PID and timestamp are not suppressed.
  config.log_formatter = ::Logger::Formatter.new

  # Use a different logger for distributed setups.
  # require "syslog/logger"
  # config.logger = ActiveSupport::TaggedLogging.new(Syslog::Logger.new "app-name")

  # Rails 7.1+ logs to STDOUT by default in production
  # Always log to both STDOUT (for Navigator/Vector capture) and log files (for debugging)

  # Determine log directory - use RAILS_LOG_VOLUME if set, otherwise Rails.root/log
  log_dir = ENV['RAILS_LOG_VOLUME'] || Rails.root.join('log').to_s
  log_file = "#{log_dir}/#{ENV['RAILS_APP_DB']}.log"

  # Ensure log directory exists
  FileUtils.mkdir_p(log_dir) unless Dir.exist?(log_dir)

  # Configure JSON logging if environment variable is set
  if ENV["RAILS_LOG_JSON"].present?
    stdout_logger = ActiveSupport::Logger.new(STDOUT)
    file_logger = ActiveSupport::Logger.new(log_file, 3)

    if defined? ActiveSupport::BroadcastLogger
      logger = ActiveSupport::BroadcastLogger.new(file_logger, stdout_logger)
    else
      logger = stdout_logger.extend ActiveSupport::Logger.broadcast(file_logger)
    end

    # Use JsonTaggedLogging to include request_id in JSON logs
    config.logger = JsonTaggedLogging.new(logger)
  else
    # Standard logging format
    stdout_logger = ActiveSupport::Logger.new(STDOUT)
    stdout_logger.formatter = config.log_formatter

    file_logger = ActiveSupport::Logger.new(log_file, 3)
    file_logger.formatter = config.log_formatter

    if defined? ActiveSupport::BroadcastLogger
      logger = ActiveSupport::BroadcastLogger.new(file_logger, stdout_logger)
    else
      logger = stdout_logger.extend ActiveSupport::Logger.broadcast(file_logger)
    end

    config.logger = ActiveSupport::TaggedLogging.new(logger)
  end

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # scoped storage
  if ENV['RAILS_APP_SCOPE']
    config.active_storage.routes_prefix = File.join(ENV['RAILS_APP_SCOPE'], 'storage')
  end
end
