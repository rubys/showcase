require 'open3'

class ConfigUpdateJob < ApplicationJob
  queue_as :default

  def perform(user_id = nil, target: 'fly')
    Rails.logger.info "ConfigUpdateJob: Starting configuration update (target: #{target})"
    database = ENV['RAILS_APP_DB']

    # This job runs script/config-update which:
    # 1. Syncs index.sqlite3 to S3 (or skips if Kamal target without S3 credentials)
    # 2. Gets list of deployment targets (Fly machines or Kamal server)
    # 3. POSTs to update_config endpoint on each target
    # 4. Each target updates htpasswd, maps, navigator config, and triggers prerender

    broadcast(user_id, database, 'processing', 0, 'Starting configuration update...')

    script_path = Rails.root.join('script/config-update').to_s

    # Build command with target flag
    cmd_args = [RbConfig.ruby, script_path]
    cmd_args += ['--target', target.to_s] if target != 'fly'

    # Disconnect database connections before spawning subprocess
    # This prevents inherited connections from causing hangs in child processes
    ActiveRecord::Base.connection_pool.disconnect!

    # Stream the output and parse it for progress
    Open3.popen3(*cmd_args) do |stdin, stdout, stderr, wait_thr|
      stdin.close

      machine_count = 0
      machines_updated = 0

      stdout.each_line do |line|
        Rails.logger.info "ConfigUpdateJob: #{line.chomp}"

        # Parse progress from output
        if line.include?('Step 1: Syncing index database')
          broadcast(user_id, database, 'processing', 10, 'Syncing index database...')
        elsif line =~ /Will update (\d+) active machines/
          machine_count = $1.to_i
          broadcast(user_id, database, 'processing', 30, "Found #{machine_count} machines to update...")
        elsif line.include?('Step 3: Triggering configuration update')
          broadcast(user_id, database, 'processing', 40, 'Updating machines...')
        elsif line.include?('✓ Success')
          machines_updated += 1
          if machine_count > 0
            progress = 40 + (machines_updated.to_f / machine_count * 50).to_i
            broadcast(user_id, database, 'processing', progress, "Updated #{machines_updated}/#{machine_count} machines...")
          end
        end
      end

      status = wait_thr.value

      stderr_output = stderr.read
      Rails.logger.warn "ConfigUpdateJob stderr:\n#{stderr_output}" unless stderr_output.empty?

      if status.success?
        # Copy current state to deployed state after successful update
        dbpath = ENV['RAILS_DB_VOLUME'] || Rails.root.join('db').to_s
        current_file = File.join(dbpath, 'showcases.yml')
        deployed_file = Rails.root.join('db/deployed-showcases.yml')
        FileUtils.cp(current_file, deployed_file) if File.exist?(current_file)

        Rails.logger.info "ConfigUpdateJob: Updated deployed state snapshot"
        Rails.logger.info "ConfigUpdateJob: Completed successfully"
        broadcast(user_id, database, 'completed', 100, 'Configuration update complete!')
      else
        Rails.logger.error "ConfigUpdateJob: Failed with exit code #{status.exitstatus}"
        broadcast(user_id, database, 'error', 0, 'Configuration update failed')
        raise "Configuration update failed with exit code #{status.exitstatus}"
      end
    end
  end

  private

  def broadcast(user_id, database, status, progress, message)
    return unless user_id && database

    stream_name = "config_update_#{database}_#{user_id}"

    TurboCable::Broadcastable.broadcast_json(
      stream_name,
      { status: status, progress: progress, message: message }
    )
  rescue => e
    Rails.logger.error "ConfigUpdateJob: Broadcast failed: #{e.class} - #{e.message}"
  end
end
