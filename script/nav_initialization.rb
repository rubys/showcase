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

# Sync databases from S3
puts "Syncing databases from S3..."
system "ruby #{git_path}/script/sync_databases_s3.rb --index-only --quiet"

# Update htpasswd file
puts "Updating htpasswd file..."
HtpasswdUpdater.update

# Run prerender in background
puts "Starting prerender..."
prerender_thread = Thread.new { system 'bin/prerender' }

# Set cable port for navigator config
ENV['CABLE_PORT'] = '28080'

# Generate full navigator configuration
puts "Generating navigator configuration..."
system "bin/rails nav:config"

# Setup demo directories
FileUtils.mkdir_p "/demo/db"
FileUtils.mkdir_p "/demo/storage/demo"
system "chown rails:rails /demo /demo/db /demo/storage/demo"

# Wait for prerender to complete
puts "Waiting for prerender to complete..."
prerender_thread.join

# Fix ownership of inventory.json if needed
inventory_file = "#{git_path}/tmp/inventory.json"
if File.exist?(inventory_file)
  stat = File.stat(inventory_file)
  if stat.uid == 0
    puts "Fixing ownership of #{inventory_file}"
    system "chown rails:rails #{inventory_file}"
  end
end

puts "Initialization complete - navigator will auto-reload config/navigator.yml"
exit 0
