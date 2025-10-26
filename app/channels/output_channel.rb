require 'pty'

class OutputChannel < ApplicationCable::Channel
  REGISTRY = Rails.root.join('tmp/tokens.yaml')

  COMMANDS = {
    apply: ->(params) {
      [RbConfig.ruby, "bin/apply-changes.rb"]
    },
    scopy: ->(params) {
      ["scopy"]
    },
    hetzner: ->(params) {
      ["showcase", "-h"]
    },
    flyio: ->(params) {
      ["showcase", "-f"]
    },
    vscode: ->(params) {
      ["showcase", "-e"]
    },
    db_browser: ->(params) {
      db_path = Rails.root.join("db", ENV['RAILS_APP_DB'] + ".sqlite3").to_s
      ["open", "-a", "/Applications/DB Browser for SQLite.app", db_path]
    }
  }

  def subscribed
    @stream = params[:stream]
    @pid = nil

    # Reload registry from disk to catch recently registered tokens
    registry = YAML.load_file(REGISTRY) rescue {}
    stream_from @stream if registry[@stream]
  end

  def command(data)
    Rails.logger.info("Command data: #{data.inspect}")
    Rails.logger.info("Stream: #{@stream.inspect}")

    # Wait up to 2 seconds for the command to appear in the registry
    # Reload registry from disk each time to catch recent writes
    block = nil
    command_type = nil
    20.times do |i|
      # Force reload from disk to catch any recent writes
      registry = YAML.load_file(REGISTRY) rescue {}
      command_type = registry[@stream]
      block = COMMANDS[command_type]
      
      if block
        Rails.logger.info("Found command #{command_type} for stream #{@stream} after #{i * 0.1}s")
        break
      end
      
      sleep 0.1
    end

    if block.nil?
      Rails.logger.error("Command not found for stream: #{@stream}")
      Rails.logger.error("Available tokens in registry: #{(YAML.load_file(REGISTRY) rescue {}).keys.last(5).inspect}")
      transmit "Error: Command not found. Please refresh and try again.\n"
    else
      Rails.logger.info("Executing command: #{command_type}")
      run(block.call(data))
    end

    transmit "\u0004"
    stop_stream_from @stream
    @pid = nil
  end

  def unsubscribed
    Process.kill("KILL", @pid) if @pid
  end

private
  def self.registry
    YAML.load_file(REGISTRY) || {}
  rescue
    {}
  end

  BLOCK_SIZE = 4096

  def self.register(command)
    # Use a consistent timestamp format - milliseconds since epoch as integer
    # This avoids floating point string conversion issues
    timestamp = (Time.now.to_f * 1000000).to_i
    token = "#{timestamp}_#{SecureRandom.base64(12)}"

    registry = self.registry

    # Ensure token is unique (very unlikely but just in case)
    while registry.key?(token)
      sleep 0.001 # Wait 1ms to ensure different timestamp
      timestamp = (Time.now.to_f * 1000000).to_i
      token = "#{timestamp}_#{SecureRandom.base64(12)}"
    end

    Rails.logger.info("Registering command: #{command.inspect} with token: #{token}")

    # Add the new token first
    registry[token] = command

    # Then clean up old entries, keeping the most recent 50 (increased to reduce race conditions)
    # This ensures we don't accidentally remove recently created tokens
    # IMPORTANT: Sort AFTER adding the new token so it's included in the sort
    if registry.length > 50
      # Sort by timestamp (embedded in token) and keep the most recent
      # Parse as integer to ensure consistent sorting
      sorted_entries = registry.to_a.sort_by { |k, v| k.split('_').first.to_i }.last(50)
      registry = sorted_entries.to_h
    end

    IO.write REGISTRY, YAML.dump(registry)

    token
  end

  def self.send(stream, message)
    # Broadcast message to a specific stream (used by trigger_config_update)
    ActionCable.server.broadcast(stream, message)
  end

  def html(string)
    Ansi::To::Html.new(string).to_html
  end

  def run(command)
    path = ENV['PATH']

    if Dir.exist? "/opt/homebrew/opt/ruby/bin"
      path = "/opt/homebrew/opt/ruby/bin:#{path}"
    end

    PTY.spawn({"PATH" => path}, *command) do |read, write, pid|
      @pid = pid
      write.close

      transmit read.readpartial(BLOCK_SIZE) while not read.eof

    rescue EOFError
    rescue Interrupt
    rescue => e
      Rails.logger.error("OutputChannel error: #{e}")

    ensure
      read.close
    end
  end
end
