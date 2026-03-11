#!/usr/bin/env ruby
# CGI script for intelligent configuration updates
# Fetches index DB from S3, regenerates all configurations
# Triggers Navigator reload via config modification timestamp

require 'bundler/setup'
require 'fileutils'
require 'open3'
require 'json'
require 'yaml'
require 'zlib'
require 'stringio'

# Set up Rails environment variable (but don't load Rails)
ENV['RAILS_ENV'] ||= 'production'

# Use manual path resolution - no Rails dependency
SCRIPT_ROOT = File.realpath(File.expand_path('..', __dir__))

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

  # Operation 1: Database sync (receive from POST or fetch from S3)
  log ""
  log "Operation 1/5: Updating index database"
  log "-" * 70

  dbpath = ENV.fetch('RAILS_DB_VOLUME') { File.join(SCRIPT_ROOT, 'db') }
  index_db_path = File.join(dbpath, 'index.sqlite3')

  # Check if database was sent directly via POST (avoids S3 eventual consistency issues)
  if ENV['REQUEST_METHOD'] == 'POST' && ENV['CONTENT_LENGTH'].to_i > 0
    begin
      body = STDIN.read(ENV['CONTENT_LENGTH'].to_i)
      update_time = ENV['HTTP_X_UPDATE_TIME']

      # Decompress if gzipped
      if ENV['HTTP_CONTENT_ENCODING'] == 'gzip'
        body = Zlib::GzipReader.new(StringIO.new(body)).read
      end

      # Write directly to disk
      File.binwrite(index_db_path, body)
      log "SUCCESS: Received database directly (#{body.bytesize} bytes, updated: #{update_time})"
    rescue => e
      log "ERROR: Failed to receive database: #{e.message}"
      log e.backtrace.first(5).join("\n")
      log ""
      log "=" * 70
      log "Configuration update FAILED (database receive failed)"
      log "Total time: #{(Time.now - start_time).round(2)}s"
      exit 1
    end
  else
    # Fall back to S3 fetch for backwards compatibility (e.g., manual triggers)
    log "No database in POST body, fetching from S3..."
    script_path = File.join(SCRIPT_ROOT, 'script', 'sync_databases_s3.rb')
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
  end

  # Operation 1.5: Download map ERB templates
  log ""
  log "Operation 1.5/5: Downloading map ERB templates"
  log "-" * 70

  begin
    require File.join(SCRIPT_ROOT, 'lib/map_downloader')
    result = MapDownloader.download(rails_root: SCRIPT_ROOT)

    if result[:downloaded].any?
      log "SUCCESS: Downloaded #{result[:downloaded].length} map(s): #{result[:downloaded].join(', ')}"
    else
      log "INFO: Maps up to date (#{result[:skipped].length} skipped)"
    end
  rescue => e
    log "WARNING: Map download failed: #{e.message}"
    log "Continuing with existing maps..."
    # Don't fail the update - maps are optional and fallback to git-tracked versions
  end

  # Operation 2: htpasswd update
  log ""
  log "Operation 2/5: Updating htpasswd file"
  log "-" * 70

  begin
    require File.join(SCRIPT_ROOT, 'lib/htpasswd_updater')
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
  log "Operation 3/5: Generating showcases configuration"
  log "-" * 70

  begin
    require File.join(SCRIPT_ROOT, 'lib/region_configuration')

    # Generate showcases.yml
    showcases_data = RegionConfiguration.generate_showcases_data
    showcases_file = File.join(dbpath, 'showcases.yml')
    File.write(showcases_file, YAML.dump(showcases_data))

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
  log "Operation 4/5: Generating navigator configuration"
  log "-" * 70

  begin
    require File.join(SCRIPT_ROOT, 'lib/navigator_config_generator')
    NavigatorConfigGenerator.generate_navigator_config
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

  # Operation 5: Prepare new event databases
  # Create databases that don't exist yet BEFORE Navigator reloads config.
  # This prevents a race condition where Navigator starts routing requests
  # to a new tenant before bin/prepare.rb (in the async ready hook) has
  # created and chowned the database, causing ReadOnlyException errors.
  log ""
  log "Operation 5/5: Preparing new event databases"
  log "-" * 70

  begin
    new_db_count = 0
    prepare_script = File.join(SCRIPT_ROOT, 'bin/prepare.rb')
    current_region = ENV['FLY_REGION']

    showcases_data.each do |year, sites|
      next unless sites.is_a?(Hash)
      sites.each do |token, info|
        next unless info.is_a?(Hash)
        # Only create databases for this machine's region
        next unless info[:region] && current_region == info[:region]

        if info[:events]
          info[:events].each do |subtoken, _|
            db_path = File.join(dbpath, "#{year}-#{token}-#{subtoken}.sqlite3")
            unless File.exist?(db_path) && File.size(db_path) > 0
              log "Preparing new database: #{File.basename(db_path)}"
              system('ruby', prepare_script, db_path)
              new_db_count += 1
            end
          end
        else
          db_path = File.join(dbpath, "#{year}-#{token}.sqlite3")
          unless File.exist?(db_path) && File.size(db_path) > 0
            log "Preparing new database: #{File.basename(db_path)}"
            system('ruby', prepare_script, db_path)
            new_db_count += 1
          end
        end
      end
    end

    if new_db_count > 0
      log "SUCCESS: Prepared #{new_db_count} new database(s)"
    else
      log "INFO: No new databases to prepare"
    end
  rescue => e
    log "WARNING: Database preparation failed: #{e.message}"
    log "Continuing - ready hook will retry database preparation"
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
