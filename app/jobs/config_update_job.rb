require 'open3'

class ConfigUpdateJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "ConfigUpdateJob: Starting configuration update"

    # This job runs script/config-update which:
    # 1. Syncs index.sqlite3 to S3
    # 2. Gets list of all active Fly machines
    # 3. POSTs to /showcase/update_config on each machine
    # 4. Each machine updates htpasswd, maps, navigator config, and triggers prerender

    script_path = Rails.root.join('script/config-update').to_s

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, script_path)

    Rails.logger.info "ConfigUpdateJob stdout:\n#{stdout}" unless stdout.empty?
    Rails.logger.warn "ConfigUpdateJob stderr:\n#{stderr}" unless stderr.empty?

    if status.success?
      Rails.logger.info "ConfigUpdateJob: Completed successfully"
    else
      Rails.logger.error "ConfigUpdateJob: Failed with exit code #{status.exitstatus}"
      raise "Configuration update failed with exit code #{status.exitstatus}"
    end
  end
end
