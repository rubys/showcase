#!/usr/bin/env ruby
# Navigator initialization script
# This runs once as a Navigator ready hook during container startup.
# It performs all initialization tasks and generates the full navigator configuration.

# Wrap entire script in error handler to show failures
begin
  require 'bundler/setup'
  require 'fileutils'
  require_relative '../lib/htpasswd_updater'

# Environment detection
def fly_io?
  ENV['FLY_APP_NAME']
end

def kamal?
  ENV['KAMAL_CONTAINER_NAME'] && !fly_io?
end

# Check for required environment variables (Fly.io only)
if fly_io?
  require 'aws-sdk-s3'

  required_env = ["AWS_SECRET_ACCESS_KEY", "AWS_ACCESS_KEY_ID", "AWS_ENDPOINT_URL_S3"]
  missing_env = required_env.select { |var| ENV[var].nil? || ENV[var].empty? }

  if !missing_env.empty?
    puts "Error: Missing required environment variables:"
    missing_env.each { |var| puts "  - #{var}" }
    exit 1
  end
end

# Setup directories
git_path = File.realpath(File.expand_path('..', __dir__))
ENV["RAILS_DB_VOLUME"] = "/data/db" if Dir.exist? "/data/db"
dbpath = ENV.fetch('RAILS_DB_VOLUME') { "#{git_path}/db" }
FileUtils.mkdir_p dbpath
# Ensure proper ownership for both Fly.io and Kamal deployments
system "chown rails:rails #{dbpath}" if fly_io? || kamal?

# Create and fix log directory ownership if needed
if ENV['RAILS_LOG_VOLUME']
  log_volume = ENV['RAILS_LOG_VOLUME']
  FileUtils.mkdir_p log_volume
  if File.exist?(log_volume)
    stat = File.stat(log_volume)
    if stat.uid == 0
      puts "Fixing ownership of #{log_volume}"
      system "chown -R rails:rails #{log_volume}"
    end
  end
end

# Setup demo tenant directories (ephemeral, not on volume)
if fly_io? || kamal?
  FileUtils.mkdir_p "/demo/db"
  FileUtils.mkdir_p "/demo/storage/demo"
  system "chown -R rails:rails /demo"
end

# Run independent operations in parallel for faster startup
threads = []

# Thread 1: S3 sync (slowest operation, ~3s) - Fly.io only
if fly_io?
  threads << Thread.new do
    puts "Syncing databases from S3..."
    system "ruby #{git_path}/script/sync_databases_s3.rb --index-only --safe --quiet"
    puts "  ✓ S3 sync complete"
  end
end

# Thread 2: Update htpasswd file (fast, but independent)
threads << Thread.new do
  puts "Updating htpasswd file..."
  HtpasswdUpdater.update
  puts "  ✓ htpasswd updated"
end

# Wait for parallel operations to complete
threads.each(&:join)

# Generate showcases.yml (depends on S3 sync completing)
# This is critical: navigator config needs this file
# Note: We don't regenerate map.yml here - using the pre-built one from Docker image
# (would need node/makemaps.js to add projection coordinates, addressing that separately)
puts "Generating showcases configuration..."
require_relative '../lib/region_configuration'
require 'yaml'

dbpath = ENV.fetch('RAILS_DB_VOLUME') { "#{git_path}/db" }

# Generate showcases.yml
showcases_data = RegionConfiguration.generate_showcases_data
showcases_file = File.join(dbpath, 'showcases.yml')
File.write(showcases_file, YAML.dump(showcases_data))
puts "  ✓ Generated #{showcases_file}"

# Bootstrap deployed state snapshot if it doesn't exist
# This provides the initial baseline for tracking what's actually deployed
deployed_file = File.join(git_path, 'db/deployed-showcases.yml')
unless File.exist?(deployed_file)
  # On admin machine: copy from git-tracked file if available
  git_file = File.join(git_path, 'config/tenant/showcases.yml')
  if File.exist?(git_file)
    FileUtils.cp(git_file, deployed_file)
    puts "  ✓ Bootstrapped #{deployed_file} from git-tracked file"
  else
    # On production machine: use the just-generated showcases.yml
    FileUtils.cp(showcases_file, deployed_file)
    puts "  ✓ Bootstrapped #{deployed_file} from generated showcases.yml"
  end
end

# Set cable port for navigator config
ENV['CABLE_PORT'] = '28080'

# Generate full navigator configuration (using fast standalone script)
puts "Generating navigator configuration..."
output = `ruby #{git_path}/script/generate_navigator_config.rb 2>&1`
result = $?.success?

puts output unless output.strip.empty?

unless result
  STDERR.puts "ERROR: Failed to generate navigator configuration (exit status: #{$?.exitstatus})"
  STDERR.puts "Output: #{output}" unless output.strip.empty?
  STDERR.puts "Config file may not have been created"
  exit 1
end

puts "Initialization complete - navigator will auto-reload config/navigator.yml"
puts "Note: Prerender will run after config reload via ready hook"
exit 0

rescue => e
  STDERR.puts "\n" + "="*70
  STDERR.puts "FATAL ERROR in nav_initialization.rb:"
  STDERR.puts "="*70
  STDERR.puts "#{e.class}: #{e.message}"
  STDERR.puts "\nBacktrace:"
  STDERR.puts e.backtrace.join("\n")
  STDERR.puts "="*70
  exit 1
end
