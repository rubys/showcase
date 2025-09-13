# JSON Logger for Rails application
# Formats log entries as structured JSON for better log aggregation and analysis

# Custom formatter that outputs JSON
class JsonLogFormatter < ActiveSupport::Logger::Formatter
  def call(severity, timestamp, progname, msg)
    entry = {
      "@timestamp" => timestamp.strftime("%Y-%m-%dT%H:%M:%S.%3NZ"),
      "severity" => severity,
      "message" => format_message(msg),
      "source" => progname || "rails",
      "tenant" => ENV['RAILS_APP_DB'] || "unknown"
    }

    JSON.generate(entry) + "\n"
  end

  private

  def format_message(msg)
    case msg
    when String
      msg
    when Hash
      msg.to_json
    when Exception
      "#{msg.message} (#{msg.class})\n#{msg.backtrace&.join("\n")}"
    else
      msg.inspect
    end
  end
end

# Custom tagged logging that adds request_id to JSON output
module JsonTaggedLogging
  def self.new(logger)
    # ActiveSupport::TaggedLogging.new extends the logger with tagging methods
    tagged_logger = ActiveSupport::TaggedLogging.new(logger)
    # Create our JSON formatter that's aware of tags
    formatter = JsonTaggedFormatter.new
    # Preserve the original formatter's tags method if it exists
    if tagged_logger.formatter.respond_to?(:tagged)
      formatter.extend(ActiveSupport::TaggedLogging::Formatter)
    end
    tagged_logger.formatter = formatter
    tagged_logger
  end

  class JsonTaggedFormatter < JsonLogFormatter
    # Include the TaggedLogging::Formatter module to get tag handling
    include ActiveSupport::TaggedLogging::Formatter

    def call(severity, timestamp, progname, msg)
      entry = {
        "@timestamp" => timestamp.strftime("%Y-%m-%dT%H:%M:%S.%3NZ"),
        "severity" => severity,
        "message" => format_message(msg),
        "source" => progname || "rails",
        "tenant" => ENV['RAILS_APP_DB'] || "unknown"
      }

      # Get current tags from the TaggedLogging::Formatter
      if current_tags.any?
        # The first tag is typically the request_id when config.log_tags = [:request_id]
        entry["request_id"] = current_tags.first if current_tags.first && current_tags.first.match?(/^[\w-]+$/)
        # Add any additional tags if there are more than one
        entry["tags"] = current_tags if current_tags.length > 1
      end

      JSON.generate(entry) + "\n"
    end

    def format_message(msg)
      case msg
      when String
        msg
      when Hash
        msg.to_json
      when Exception
        "#{msg.message} (#{msg.class})\n#{msg.backtrace&.join("\n")}"
      else
        msg.inspect
      end
    end
  end
end