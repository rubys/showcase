#!/usr/bin/env ruby

require 'bundler/setup'
require 'aws-sdk-s3'
require 'fileutils'

# Check for required environment variables
required_env = ["AWS_REGION", "AWS_SECRET_ACCESS_KEY", "AWS_ACCESS_KEY_ID", "AWS_ENDPOINT_URL_S3"]
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

# Main sync logic wrapped in error handling
begin
  puts "Database Sync with S3"
  puts "=" * 50
  puts "Local path: #{dbpath}"
  puts "S3 endpoint: #{ENV['AWS_ENDPOINT_URL_S3']}"
  puts "FLY_REGION: #{ENV['FLY_REGION']}" if ENV['FLY_REGION']
  puts

  # Initialize S3 client
  s3_client = Aws::S3::Client.new(
    region: ENV['AWS_REGION'],
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

rescue => exception
end
