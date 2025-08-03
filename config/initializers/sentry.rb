if ENV["SENTRY_DSN"] and ENV["RAILS_APP_OWNER"]

Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.logger = ActiveSupport::Logger.new(STDOUT)
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]

  # Disable Sentry Uptime/Performance Monitoring
  config.enable_tracing = false

  # If you want to be extra sure, you can also set traces_sample_rate to 0.0:
  config.traces_sample_rate = 0.0
end

end
