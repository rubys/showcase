#!/usr/bin/env ruby

require 'bundler/setup'
require 'aws-sdk-s3'
require 'fileutils'
require_relative '../lib/htpasswd_updater'

# Parse command line arguments
navigator_type = 'navigator' # default
ARGV.each do |arg|
  case arg
  when '--legacy'
    navigator_type = 'legacy'
  when '--refactored'
    navigator_type = 'navigator'
  end
end

# Trap signals to understand what's happening
nav_pid = nil

Signal.trap("TERM") do
  puts "Ruby script received SIGTERM"
  Process.kill('TERM', nav_pid) if nav_pid
  exit 0
end

Signal.trap("INT") do
  puts "Ruby script received SIGINT"
  Process.kill('TERM', nav_pid) if nav_pid
  exit 0
end

begin
  FileUtils.cp 'config/navigator-maintenance.yml', 'config/navigator.yml'
  
  # Pass LOG_LEVEL to navigator if set (for debugging)
  # Can be set via environment: LOG_LEVEL=debug fly deploy
  # Navigator will inherit all environment variables by default
  nav_pid = spawn("navigator")

  # Check for required environment variables
  required_env = ["AWS_SECRET_ACCESS_KEY", "AWS_ACCESS_KEY_ID", "AWS_ENDPOINT_URL_S3"]
  missing_env = required_env.select { |var| ENV[var].nil? || ENV[var].empty? }

  if !missing_env.empty?
    puts "Error: Missing required environment variables:"
    missing_env.each { |var| puts "  - #{var}" }
    exit 1
  end

  # Load configurations
  git_path = File.realpath(File.expand_path('..', __dir__))
  ENV["RAILS_DB_VOLUME"] = "/data/db" if Dir.exist? "/data/db"
  dbpath = ENV.fetch('RAILS_DB_VOLUME') { "#{git_path}/db" }
  FileUtils.mkdir_p dbpath

  system "ruby #{git_path}/script/sync_databases_s3.rb --index-only --quiet"

  # Update htpasswd file
  HtpasswdUpdater.update

  thread = Thread.new { system 'bin/prerender' }
  ENV['CABLE_PORT'] = '28080'

  # Use the appropriate navigator configuration task
  rake_task = navigator_type == 'legacy' ? 'nav:legacy' : 'nav:config'
  system "bin/rails #{rake_task}"

  FileUtils.mkdir_p "/demo/db"
  FileUtils.mkdir_p "/demo/storage/demo"
  Process.kill('HUP', nav_pid)
  thread.join

  # Wait for navigator to exit (which should never happen in normal operation)
  Process.wait(nav_pid)
  exit $?.exitstatus

rescue => exception
  ## TODO: sentry alerts
end
