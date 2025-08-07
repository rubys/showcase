#!/usr/bin/env ruby

require 'yaml'
require 'fileutils'
require 'optparse'
require 'bundler/setup'
require 'aws-sdk-s3'

# Parse command line arguments
options = { dry_run: false, verbose: false }
OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"
  
  opts.on("--dry-run", "Show what would be done without making changes") do
    options[:dry_run] = true
  end
  
  opts.on("-v", "--verbose", "Verbose output") do
    options[:verbose] = true
  end
  
  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end
end.parse!

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
showcases = YAML.load_file("#{git_path}/config/tenant/showcases.yml")

# Build tenant hash from nginx-config.rb logic
# Also track regions for each tenant
tenants = {}
tenant_regions = {}

# Add index tenant (no region restriction for index)
tenants["index"] = "index"
tenant_regions["index"] = nil

# Process showcases to build tenant list
showcases.each do |year, list|
  list.each do |token, info|
    region = info[:region]
    if info[:events]
      info[:events].each do |subtoken, subinfo|
        label = "#{year}-#{token}-#{subtoken}"
        name = info[:name] + ' - ' + subinfo[:name]
        tenants[label] = name
        tenant_regions[label] = region
      end
    else
      label = "#{year}-#{token}"
      name = info[:name]
      tenants[label] = name
      tenant_regions[label] = region
    end
  end
end

# Add demo tenant if running in a region (no region restriction for demo)
if ENV['FLY_REGION'] || ENV['KAMAL_CONTAINER_NAME']
  tenants["demo"] = "Demo"
  tenant_regions["demo"] = nil
end

# Get list of expected database names
expected_databases = tenants.keys.map { |label| "#{label}.sqlite3" }

puts "Database Sync with S3"
puts "=" * 50
puts "Local path: #{dbpath}"
puts "S3 endpoint: #{ENV['AWS_ENDPOINT_URL_S3']}"
puts "Total tenants: #{tenants.size}"
puts "FLY_REGION: #{ENV['FLY_REGION']}" if ENV['FLY_REGION']
puts "Dry run: #{options[:dry_run]}" if options[:dry_run]
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
bucket_name = ENV.fetch('S3_BUCKET', 'showcase-databases')

# Ensure bucket exists
begin
  s3_client.head_bucket(bucket: bucket_name)
rescue Aws::S3::Errors::NotFound
  puts "Creating bucket: #{bucket_name}"
  s3_client.create_bucket(bucket: bucket_name) unless options[:dry_run]
end

# Get list of objects in S3 with "db/" prefix (handle pagination)
s3_objects = {}
begin
  continuation_token = nil
  loop do
    params = {
      bucket: bucket_name,
      prefix: "db/",
      max_keys: 1000
    }
    params[:continuation_token] = continuation_token if continuation_token
    
    response = s3_client.list_objects_v2(params)
    
    if response.contents
      response.contents.each do |object|
        # Extract filename from key (remove "db/" prefix)
        filename = object.key.sub(/^db\//, '')
        s3_objects[filename] = {
          last_modified: object.last_modified,
          size: object.size,
          etag: object.etag
        }
      end
    end
    
    # Check if there are more results
    break unless response.is_truncated
    continuation_token = response.next_continuation_token
  end
rescue => e
  puts "Error listing S3 objects: #{e.message}"
  exit 1
end

puts "S3 objects found: #{s3_objects.size}"
puts

# Track actions
downloads = []
uploads = []
skipped = []

# Process each expected database
expected_databases.each do |db_name|
  local_path = File.join(dbpath, db_name)
  s3_key = "db/#{db_name}"
  
  local_exists = File.exist?(local_path) && !File.symlink?(local_path)
  s3_exists = s3_objects.key?(db_name)
  
  # Extract tenant name from database name (remove .sqlite3 extension)
  tenant_name = db_name.sub(/\.sqlite3$/, '')
  
  # Check if uploads are allowed for this database based on FLY_REGION
  allow_upload = true
  if ENV['FLY_REGION'] && tenant_regions[tenant_name]
    # Only allow upload if this region owns the database
    allow_upload = (ENV['FLY_REGION'] == tenant_regions[tenant_name])
  end
  
  if local_exists && s3_exists
    # Both exist - compare timestamps
    local_mtime = File.mtime(local_path)
    s3_mtime = s3_objects[db_name][:last_modified]
    
    if s3_mtime > local_mtime
      # S3 is newer - download
      downloads << { name: db_name, local_mtime: local_mtime, s3_mtime: s3_mtime }
      
      puts "Download: #{db_name}" if options[:verbose]
      puts "  S3: #{s3_mtime.strftime('%Y-%m-%d %H:%M:%S')}" if options[:verbose]
      puts "  Local: #{local_mtime.strftime('%Y-%m-%d %H:%M:%S')}" if options[:verbose]
      
      unless options[:dry_run]
        begin
          response = s3_client.get_object(bucket: bucket_name, key: s3_key)
          File.open(local_path, 'wb') do |file|
            file.write(response.body.read)
          end
          # Preserve S3 modification time
          File.utime(s3_mtime, s3_mtime, local_path)
        rescue => e
          puts "  Error downloading: #{e.message}"
        end
      end
      
    elsif local_mtime > s3_mtime
      # Local is newer - upload (if allowed)
      if allow_upload
        uploads << { name: db_name, local_mtime: local_mtime, s3_mtime: s3_mtime }
        
        puts "Upload: #{db_name}" if options[:verbose]
        puts "  Local: #{local_mtime.strftime('%Y-%m-%d %H:%M:%S')}" if options[:verbose]
        puts "  S3: #{s3_mtime.strftime('%Y-%m-%d %H:%M:%S')}" if options[:verbose]
        
        unless options[:dry_run]
          begin
            File.open(local_path, 'rb') do |file|
              s3_client.put_object(
                bucket: bucket_name,
                key: s3_key,
                body: file,
                metadata: {
                  'last-modified' => local_mtime.to_s
                }
              )
            end
          rescue => e
            puts "  Error uploading: #{e.message}"
          end
        end
      else
        skipped << db_name
        puts "Skip (region mismatch): #{db_name} (belongs to #{tenant_regions[tenant_name]}, current region: #{ENV['FLY_REGION']})" if options[:verbose]
      end
      
    else
      # Same timestamp - skip
      skipped << db_name
      puts "Skip (same): #{db_name}" if options[:verbose]
    end
    
  elsif local_exists && !s3_exists
    # Only local exists - upload (if allowed)
    if allow_upload
      local_mtime = File.mtime(local_path)
      uploads << { name: db_name, local_mtime: local_mtime, s3_mtime: nil }
      
      puts "Upload (new): #{db_name}" if options[:verbose]
      puts "  Local: #{local_mtime.strftime('%Y-%m-%d %H:%M:%S')}" if options[:verbose]
      
      unless options[:dry_run]
        begin
          File.open(local_path, 'rb') do |file|
            s3_client.put_object(
              bucket: bucket_name,
              key: s3_key,
              body: file,
              metadata: {
                'last-modified' => local_mtime.to_s
              }
            )
          end
        rescue => e
          puts "  Error uploading: #{e.message}"
        end
      end
    else
      puts "Skip (region mismatch): #{db_name} (belongs to #{tenant_regions[tenant_name]}, current region: #{ENV['FLY_REGION']})" if options[:verbose]
    end
    
  elsif !local_exists && s3_exists
    # Only S3 exists - download
    s3_mtime = s3_objects[db_name][:last_modified]
    downloads << { name: db_name, local_mtime: nil, s3_mtime: s3_mtime }
    
    puts "Download (new): #{db_name}" if options[:verbose]
    puts "  S3: #{s3_mtime.strftime('%Y-%m-%d %H:%M:%S')}" if options[:verbose]
    
    unless options[:dry_run]
      begin
        response = s3_client.get_object(bucket: bucket_name, key: s3_key)
        File.open(local_path, 'wb') do |file|
          file.write(response.body.read)
        end
        # Preserve S3 modification time
        File.utime(s3_mtime, s3_mtime, local_path)
      rescue => e
        puts "  Error downloading: #{e.message}"
      end
    end
    
  else
    # Neither exists (shouldn't happen for tenants, but handle gracefully)
    puts "Missing both locally and in S3: #{db_name}" if options[:verbose]
  end
end

# Report ignored S3 objects (not in tenant list)
s3_only = s3_objects.keys - expected_databases
if !s3_only.empty? && options[:verbose]
  puts
  puts "Ignored S3 objects (not in tenant list):"
  s3_only.sort.each do |name|
    puts "  - #{name}"
  end
end

# Summary
puts
puts "Summary:"
puts "=" * 50
puts "Downloads: #{downloads.size}"
downloads.each do |d|
  puts "  - #{d[:name]}"
end if !downloads.empty?

puts "Uploads: #{uploads.size}"
uploads.each do |u|
  puts "  - #{u[:name]}"
end if !uploads.empty?

puts "Skipped (unchanged): #{skipped.size}" if options[:verbose]
puts
puts "Sync complete#{options[:dry_run] ? ' (dry run - no changes made)' : ''}."