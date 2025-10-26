#!/usr/bin/env ruby
# CGI script for intelligent configuration updates
# Fetches index DB from S3, regenerates all configurations
# Triggers Navigator reload via config modification timestamp

require 'bundler/setup'
require 'fileutils'
require 'open3'
require 'json'
require 'yaml'

# Set up Rails environment for model/lib access
ENV['RAILS_ENV'] ||= 'production'
require_relative '../config/environment'

# CGI response helpers
def cgi_header(content_type = 'text/plain')
  puts "Content-Type: #{content_type}"
  puts ""
  STDOUT.flush
end

def log(message)
  timestamp = Time.now.utc.iso8601
  puts "[#{timestamp}] #{message}"
  STDOUT.flush
end

def run_command(description, *args)
  log "#{description}..."
  stdout, stderr, status = Open3.capture3(*args)

  # Echo output for monitoring
  puts stdout unless stdout.empty?
  puts stderr unless stderr.empty?

  unless status.success?
    log "ERROR: #{description} failed (exit code: #{status.exitstatus})"
    return false
  end

  log "SUCCESS: #{description} completed"
  true
end

# Main execution
begin
  cgi_header
  log "Starting configuration update (Phase 1: Fast operations)"
  log "=" * 70

  # Track start time for measuring performance
  start_time = Time.now

  # Operation 1: Database sync (fetch index.sqlite3 from S3)
  log ""
  log "Operation 1/4: Fetching index database from S3"
  log "-" * 70

  script_path = Rails.root.join('script', 'sync_databases_s3.rb').to_s
  unless run_command(
    "Database sync",
    'ruby', script_path, '--index-only'
  )
    log ""
    log "=" * 70
    log "Configuration update FAILED (database sync failed)"
    log "Total time: #{(Time.now - start_time).round(2)}s"
    exit 1
  end

  # Operation 2: htpasswd update
  log ""
  log "Operation 2/4: Updating htpasswd file"
  log "-" * 70

  begin
    require Rails.root.join('lib/htpasswd_updater').to_s
    HtpasswdUpdater.update
    log "SUCCESS: htpasswd updated"
  rescue => e
    log "ERROR: htpasswd update failed: #{e.message}"
    log e.backtrace.first(5).join("\n")
    log ""
    log "=" * 70
    log "Configuration update FAILED (htpasswd update failed)"
    log "Total time: #{(Time.now - start_time).round(2)}s"
    exit 1
  end

  # Operation 3: Showcases generation
  log ""
  log "Operation 3/4: Generating showcases configuration"
  log "-" * 70

  begin
    require Rails.root.join('lib/region_configuration').to_s

    dbpath = ENV.fetch('RAILS_DB_VOLUME') { Rails.root.join('db').to_s }

    # Generate showcases.yml
    showcases_data = RegionConfiguration.generate_showcases_data
    showcases_file = File.join(dbpath, 'showcases.yml')
    File.write(showcases_file, YAML.dump(showcases_data))

    # Note: Not regenerating map.yml here - using pre-built one from Docker image
    # (would need node/makemaps.js to add projection coordinates)

    log "SUCCESS: Showcases configuration generated"
  rescue => e
    log "ERROR: Showcases generation failed: #{e.message}"
    log e.backtrace.first(5).join("\n")
    log ""
    log "=" * 70
    log "Configuration update FAILED (showcases generation failed)"
    log "Total time: #{(Time.now - start_time).round(2)}s"
    exit 1
  end

  # Operation 4: Navigator config generation
  log ""
  log "Operation 4/4: Generating navigator configuration"
  log "-" * 70

  begin
    configurator = AdminController.new
    configurator.generate_navigator_config
    log "SUCCESS: Navigator configuration generated"
  rescue => e
    log "ERROR: Navigator config generation failed: #{e.message}"
    log e.backtrace.first(5).join("\n")
    log ""
    log "=" * 70
    log "Configuration update FAILED (navigator config generation failed)"
    log "Total time: #{(Time.now - start_time).round(2)}s"
    exit 1
  end

  # Success summary
  log ""
  log "=" * 70
  log "Configuration update COMPLETED successfully"
  log "Total time: #{(Time.now - start_time).round(2)}s"
  log ""
  log "Navigator will detect config changes and reload automatically"
  log "Post-reload hook will run prerender and event database updates"
  log "=" * 70

  exit 0

rescue => e
  log ""
  log "FATAL ERROR: #{e.class}: #{e.message}"
  log e.backtrace.join("\n")
  log ""
  log "=" * 70
  log "Configuration update FAILED (unexpected error)"
  exit 1
end
