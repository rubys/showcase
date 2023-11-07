require 'open3'

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
    regitry.pop while registry.length > 12
    registry = registry.to_h

    registry[token] = command
    IO.write REGISTRY, YAML.dump(registry)

    token
  end

  def html(string)
    Ansi::To::Html.new(string).to_html
  end

  def run(command)
    Open3.popen3(*command) do |stdin, stdout, stderr, wait_thr|
      @pid = wait_thr.pid
      files = [stdout, stderr]
      stdin.close_write
    
      part = { stdout => "", stderr => "" }
    
      until files.all? {|file| file.eof} do
        ready = IO.select(files)
        next unless ready
        ready[0].each do |f|
          lines = f.read_nonblock(BLOCK_SIZE).split("\n", -1)
          next if lines.empty?
          lines[0] = part[f] + lines[0] unless part[f].empty?
          part[f] = lines.pop()
          lines.each {|line| transmit html(line)}
          rescue EOFError => e
        end
      end
    
      part.values.each do |part|
        transmit html(part) unless part.empty?
      end

      files.each {|file| file.close}

      @pid = nil
    
    rescue Interrupt
    rescue => e
      puts e.to_s
      
    ensure
      files.each {|file| file.close}
      @pid = nil
    end    
  end
end
