if ENV["SENTRY_DSN"] and ENV["RAILS_APP_OWNER"]

Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.sdk_logger = ActiveSupport::Logger.new(STDOUT)
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]

  # Disable Sentry Uptime/Performance Monitoring
  # Using traces_sample_rate = 0.0 instead of deprecated enable_tracing
  config.traces_sample_rate = 0.0
end

end
