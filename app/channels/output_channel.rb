require 'open3'

class OutputChannel < ApplicationCable::Channel
  def subscribed
    @stream = params[:stream]
    @pid = nil
    stream_from @stream if @@registry[@stream]
  end

  def command(data)
    block = @@registry[@stream]
    run(block.call(data)) if block
  end

  def unsubscribed
    Process.kill("KILL", @pid) if @pid
  end

private
  @@registry = {}

  BLOCK_SIZE = 4096

  def self.register(&block)
    token = SecureRandom.base64(15)
    @@registry[token] = block
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
