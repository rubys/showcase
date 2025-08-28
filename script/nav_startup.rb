#!/usr/bin/env ruby

require 'bundler/setup'
require 'aws-sdk-s3'
require 'fileutils'

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

  puts "Fetch index.sqlite3 from S3"

  # Initialize S3 client
  s3_client = Aws::S3::Client.new(
    region: ENV.fetch('AWS_REGION', 'auto'),
    access_key_id: ENV['AWS_ACCESS_KEY_ID'],
    secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
    endpoint: ENV['AWS_ENDPOINT_URL_S3'],
    force_path_style: true
  )

  # Extract bucket name from endpoint or use default
  bucket_name = ENV.fetch('BUCKET_NAME', 'showcase')

  # Ensure bucket exists
  begin
    s3_client.head_bucket(bucket: bucket_name)
  rescue Aws::S3::Errors::NotFound
    puts "Bucket not found: #{bucket_name}"
    exit 1
  end

  # Process each expected database
  db_name = "index.sqlite3"
  local_path = File.join(dbpath, db_name)
  s3_key = "db/#{db_name}"
  
  response = s3_client.get_object(bucket: bucket_name, key: s3_key)
  File.open(local_path, 'wb') do |file|
    file.write(response.body.read)
  end

  thread = Thread.new { system 'bin/prerender' }
  system 'bin/rails nav:config'
  Process.kill('HUP', nav_pid)
  thread.join

  # Wait for navigator to exit (which should never happen in normal operation)
  Process.wait(nav_pid)
  exit $?.exitstatus

rescue => exception
  ## TODO: sentry alerts
end
