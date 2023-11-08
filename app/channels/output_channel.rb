require 'pty'

class OutputChannel < ApplicationCable::Channel
  REGISTRY = Rails.root.join('tmp/tokens.yaml')

  COMMANDS = {
    apply: ->(params) {
      [RbConfig.ruby, "bin/apply-changes.rb"]
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
  end

  def unsubscribed
    Process.kill("KILL", @pid) if @pid
  end

private
  def self.registry
    YAML.load_file(REGISTRY) rescue {}
  end

  BLOCK_SIZE = 4096

  def self.register(command)
    token = SecureRandom.base64(15)

    registry = self.registry.to_a
    registry.pop while registry.length > 12
    registry = registry.to_h

    registry[token] = command
    IO.write REGISTRY, YAML.dump(registry)

    token
  end

  def html(string)
    Ansi::To::Html.new(string).to_html
  end

  def run(command)
    PTY.spawn *command do |read, write, pid|
      @pid = pid
      write.close
    
      transmit read.readpartial(BLOCK_SIZE) while not read.eof
    
    rescue EOFError
    rescue Interrupt
    rescue => e
      puts e.to_s
      
    ensure
      read.close
    end    
  end
end
