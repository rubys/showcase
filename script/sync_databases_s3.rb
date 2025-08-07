#!/usr/bin/env ruby

require 'bundler/setup'
require 'yaml'
require 'fileutils'
require 'optparse'
require 'aws-sdk-s3'
require 'json'

# Initialize Sentry if DSN is available
if ENV["SENTRY_DSN"]
  require 'sentry-ruby'
  
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
  end
end

# Parse command line arguments
options = { dry_run: false, verbose: false, safe: false }
OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"
  
  opts.on("--dry-run", "Show what would be done without making changes") do
    options[:dry_run] = true
  end
  
  opts.on("-v", "--verbose", "Verbose output") do
    options[:verbose] = true
  end
  
  opts.on("--safe", "Disallow downloads to current region (when FLY_REGION is set)") do
    options[:safe] = true
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

# Main sync logic wrapped in error handling
begin
  puts "Database Sync with S3"
  puts "=" * 50
  puts "Local path: #{dbpath}"
  puts "S3 endpoint: #{ENV['AWS_ENDPOINT_URL_S3']}"
  puts "Total tenants: #{tenants.size}"
  puts "FLY_REGION: #{ENV['FLY_REGION']}" if ENV['FLY_REGION']
  puts "Dry run: #{options[:dry_run]}" if options[:dry_run]
  puts "Safe mode: #{options[:safe]} (no downloads to current region)" if options[:safe] && ENV['FLY_REGION']
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
  puts "Creating bucket: #{bucket_name}"
  s3_client.create_bucket(bucket: bucket_name) unless options[:dry_run]
end

# Load inventories for all regions
# Inventory tracks: db_name => { etag: string, last_modified: timestamp }
inventories = {}
inventory_changed = {}

# Get unique regions plus 'index'
all_regions = ['index'] + tenant_regions.values.compact.uniq

puts "Loading inventories for regions: #{all_regions.join(', ')}" if options[:verbose]

all_regions.each do |region|
  inventory_key = "inventory/#{region}.json"
  inventories[region] = {}
  inventory_changed[region] = false
  
  begin
    response = s3_client.get_object(bucket: bucket_name, key: inventory_key)
    inventories[region] = JSON.parse(response.body.read)
    puts "  Loaded inventory for #{region}: #{inventories[region].size} entries" if options[:verbose]
  rescue Aws::S3::Errors::NoSuchKey
    puts "  No inventory found for #{region}, starting fresh" if options[:verbose]
  rescue => e
    puts "  Error loading inventory for #{region}: #{e.message}" if options[:verbose]
  end
end

# Determine which inventory to use for current operations
current_region = ENV['FLY_REGION'] || 'index'
current_inventory = inventories[current_region]

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
        
        # Determine which region owns this database
        tenant_name = filename.sub(/\.sqlite3$/, '')
        owner_region = tenant_regions[tenant_name] || 'index'
        
        # Check the owner region's inventory for matching etag to get actual last_modified time
        actual_last_modified = nil
        if inventories[owner_region][filename] && inventories[owner_region][filename]['etag'] == object.etag
          actual_last_modified = Time.parse(inventories[owner_region][filename]['last_modified'])
        end
        
        s3_objects[filename] = {
          last_modified: actual_last_modified || object.last_modified,
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
  error_msg = "Error listing S3 objects: #{e.message}"
  puts error_msg
  Sentry.capture_exception(e) if ENV["SENTRY_DSN"]
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
  
  # Use Time.new(0) as sentinel for non-existent files
  local_exists = File.exist?(local_path) && !File.symlink?(local_path)
  local_mtime = local_exists ? File.mtime(local_path) : Time.new(0)
  
  s3_exists = s3_objects.key?(db_name)
  s3_mtime = s3_exists ? s3_objects[db_name][:last_modified] : Time.new(0)
  
  # Extract tenant name from database name (remove .sqlite3 extension)
  tenant_name = db_name.sub(/\.sqlite3$/, '')
  
  # Check if uploads are allowed for this database based on FLY_REGION
  allow_upload = true
  if ENV['FLY_REGION'] && tenant_regions[tenant_name]
    # Only allow upload if this region owns the database
    allow_upload = (ENV['FLY_REGION'] == tenant_regions[tenant_name])
  end
  
  # Skip if neither exists
  if !local_exists && !s3_exists
    puts "Missing both locally and in S3: #{db_name}" if options[:verbose]
    next
  end
  
  # Compare timestamps (truncate to second precision to avoid microsecond differences)
  local_mtime_seconds = local_mtime.to_i
  s3_mtime_seconds = s3_mtime.to_i
  
  if s3_mtime_seconds > local_mtime_seconds
    # S3 is newer (or local doesn't exist) - download
    
    # Check if downloads are allowed when --safe is set
    # Allow download if: not in safe mode, or file doesn't exist locally, or not owned by current region
    if options[:safe] && ENV['FLY_REGION'] && tenant_regions[tenant_name] == ENV['FLY_REGION'] && local_exists
      # Skip download - this region owns this database and file exists locally
      skipped << db_name
      puts "Skip download (--safe mode, owned by current region): #{db_name}" if options[:verbose]
    else
      downloads << { name: db_name, local_mtime: local_exists ? local_mtime : nil, s3_mtime: s3_mtime }
      
      action_type = local_exists ? "Download" : "Download (new)"
      puts "#{action_type}: #{db_name}" if options[:verbose]
      puts "  S3: #{s3_mtime.strftime('%Y-%m-%d %H:%M:%S')}" if options[:verbose]
      puts "  Local: #{local_mtime.strftime('%Y-%m-%d %H:%M:%S')}" if options[:verbose] && local_exists
      
      unless options[:dry_run]
        begin
          response = s3_client.get_object(bucket: bucket_name, key: s3_key)
          File.open(local_path, 'wb') do |file|
            file.write(response.body.read)
          end
          # Preserve modification time from metadata if available, otherwise use S3 object time
          if response.metadata && response.metadata['last-modified']
            metadata_time = Time.parse(response.metadata['last-modified'])
            File.utime(metadata_time, metadata_time, local_path)
          else
            File.utime(s3_mtime, s3_mtime, local_path)
          end
        rescue => e
          error_msg = "Error downloading #{db_name}: #{e.message}"
          puts "  Error downloading: #{e.message}"
          if ENV["SENTRY_DSN"]
            Sentry.capture_message(error_msg, level: :error, extra: {
              database: db_name,
              operation: local_exists ? 'download' : 'download_new',
              s3_mtime: s3_mtime,
              local_mtime: local_exists ? local_mtime : nil
            })
          end
        end
      end
    end
    
  elsif local_mtime_seconds > s3_mtime_seconds
    # Local is newer (or S3 doesn't exist) - upload (if allowed)
    if allow_upload
      uploads << { name: db_name, local_mtime: local_mtime, s3_mtime: s3_exists ? s3_mtime : nil }
      
      action_type = s3_exists ? "Upload" : "Upload (new)"
      puts "#{action_type}: #{db_name}" if options[:verbose]
      puts "  Local: #{local_mtime.strftime('%Y-%m-%d %H:%M:%S')}" if options[:verbose]
      puts "  S3: #{s3_mtime.strftime('%Y-%m-%d %H:%M:%S')}" if options[:verbose] && s3_exists
      
      unless options[:dry_run]
        begin
          File.open(local_path, 'rb') do |file|
            put_response = s3_client.put_object(
              bucket: bucket_name,
              key: s3_key,
              body: file,
              metadata: {
                'last-modified' => local_mtime.utc.inspect
              }
            )
            
            # Update inventory for the region that owns this database
            owner_region = tenant_regions[tenant_name] || 'index'
            inventories[owner_region][db_name] = {
              'etag' => put_response.etag,
              'last_modified' => local_mtime.to_s
            }
            inventory_changed[owner_region] = true
          end
        rescue => e
          error_msg = "Error uploading #{db_name}: #{e.message}"
          puts "  Error uploading: #{e.message}"
          if ENV["SENTRY_DSN"]
            Sentry.capture_message(error_msg, level: :error, extra: {
              database: db_name,
              operation: s3_exists ? 'upload' : 'upload_new',
              local_mtime: local_mtime,
              s3_mtime: s3_exists ? s3_mtime : nil,
              region: ENV['FLY_REGION'],
              expected_region: tenant_regions[tenant_name]
            })
          end
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

# Save updated inventories
unless options[:dry_run]
  inventory_changed.each do |region, changed|
    if changed
      inventory_key = "inventory/#{region}.json"
      puts "Updating inventory for #{region}" if options[:verbose]
      
      begin
        s3_client.put_object(
          bucket: bucket_name,
          key: inventory_key,
          body: JSON.pretty_generate(inventories[region]),
          content_type: 'application/json'
        )
      rescue => e
        puts "Error saving inventory for #{region}: #{e.message}"
        if ENV["SENTRY_DSN"]
          Sentry.capture_message("Error saving inventory for #{region}: #{e.message}", level: :error)
        end
      end
    end
  end
end

puts
puts "Sync complete#{options[:dry_run] ? ' (dry run - no changes made)' : ''}."

rescue => exception
  # Capture any unexpected errors that weren't handled above
  error_msg = "Unexpected error in S3 sync: #{exception.message}"
  puts error_msg
  puts exception.backtrace.join("\n") if options[:verbose]
  
  if ENV["SENTRY_DSN"]
    Sentry.capture_exception(exception, extra: {
      fly_region: ENV['FLY_REGION'],
      dry_run: options[:dry_run],
      verbose: options[:verbose]
    })
  end
  
  exit 1
end
