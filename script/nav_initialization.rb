#!/usr/bin/env ruby
# Navigator initialization script
# This runs once as a Navigator ready hook during container startup.
# It performs all initialization tasks and generates the full navigator configuration.

require 'bundler/setup'
require 'fileutils'
require_relative '../lib/htpasswd_updater'

# Check for required environment variables
required_env = ["AWS_SECRET_ACCESS_KEY", "AWS_ACCESS_KEY_ID", "AWS_ENDPOINT_URL_S3"]
missing_env = required_env.select { |var| ENV[var].nil? || ENV[var].empty? }
if !missing_env.empty?
  puts "Error: Missing required environment variables:"
  missing_env.each { |var| puts "  - #{var}" }
  exit 1
end

# Setup directories
git_path = File.realpath(File.expand_path('..', __dir__))
ENV["RAILS_DB_VOLUME"] = "/data/db" if Dir.exist? "/data/db"
dbpath = ENV.fetch('RAILS_DB_VOLUME') { "#{git_path}/db" }
FileUtils.mkdir_p dbpath
system "chown rails:rails #{dbpath}"

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

# Run independent operations in parallel for faster startup
threads = []

# Thread 1: S3 sync (slowest operation, ~3s)
threads << Thread.new do
  puts "Syncing databases from S3..."
  system "ruby #{git_path}/script/sync_databases_s3.rb --index-only --safe --quiet"
  puts "  ✓ S3 sync complete"
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
system "ruby #{git_path}/script/generate_navigator_config.rb"

# Setup demo directories
FileUtils.mkdir_p "/demo/db"
FileUtils.mkdir_p "/demo/storage/demo"
system "chown rails:rails /demo /demo/db /demo/storage/demo"

puts "Initialization complete - navigator will auto-reload config/navigator.yml"
puts "Note: Prerender will run after config reload via ready hook"
exit 0
