class CommandExecutionJob < ApplicationJob
  queue_as :default

  # Commands map to executable blocks
  # No REGISTRY needed - HTTP authentication provides security
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

  def perform(command_type, user_id, database, params = {})
    command_sym = command_type.to_sym
    block = COMMANDS[command_sym]

    unless block
      Rails.logger.error("Unknown command: #{command_type}")
      return
    end

    stream = "command_output_#{database}_#{user_id}_#{job_id}"
    command = block.call(params)

    Rails.logger.info("Executing command: #{command_sym} via #{stream}")

    execute_command(stream, command)
  end

  private

  BLOCK_SIZE = 4096

  def execute_command(stream, command)
    require 'pty'

    path = ENV['PATH']
    if Dir.exist? "/opt/homebrew/opt/ruby/bin"
      path = "/opt/homebrew/opt/ruby/bin:#{path}"
    end

    PTY.spawn({"PATH" => path}, *command) do |read, write, pid|
      write.close

      while !read.eof
        output = read.readpartial(BLOCK_SIZE)
        ActionCable.server.broadcast(stream, output)
      end

    rescue EOFError
    rescue Interrupt
    rescue => e
      Rails.logger.error("CommandExecutionJob error: #{e}")
      ActionCable.server.broadcast(stream, "\nError: #{e.message}\n")
    ensure
      read.close
    end

    # Send completion marker
    ActionCable.server.broadcast(stream, "\u0004")
  end
end
