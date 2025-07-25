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
    }
  }

  def subscribed
    @stream = params[:stream]
    @pid = nil
    stream_from @stream if self.class.registry[@stream]
  end

  def command(data)
    block = COMMANDS[self.class.registry[@stream]]
    run(block.call(data)) if block

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
    # Generate a unique token with timestamp to avoid collisions
    token = "#{Time.now.to_f.to_s.tr('.', '')}_#{SecureRandom.base64(12)}"

    registry = self.registry
    
    # Ensure token is unique (very unlikely but just in case)
    while registry.key?(token)
      token = "#{Time.now.to_f.to_s.tr('.', '')}_#{SecureRandom.base64(12)}"
    end
    
    # Add the new token first
    registry[token] = command
    
    # Then clean up old entries, keeping the most recent 20 (increased further)
    # This ensures we don't accidentally remove recently created tokens
    if registry.length > 20
      # Sort by timestamp (embedded in token) and keep the most recent
      sorted_entries = registry.to_a.sort_by { |k, v| k.split('_').first.to_f }.last(20)
      registry = sorted_entries.to_h
    end
    
    IO.write REGISTRY, YAML.dump(registry)

    token
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
