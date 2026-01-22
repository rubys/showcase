#!/usr/bin/env ruby

require 'bundler/setup'
require 'yaml'
require 'fileutils'
require 'optparse'
require 'aws-sdk-s3'
require 'json'
require 'sqlite3'
require 'uri'
require 'net/http'

# Initialize Sentry if DSN is available
if ENV["SENTRY_DSN"]
  require 'sentry-ruby'
  
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
  end
end

# Parse command line arguments
options = { dry_run: false, verbose: false, safe: false, quiet: false, skip_list: [], only_dbs: [] }
OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"
  
  opts.on("--dry-run", "Show what would be done without making changes") do
    options[:dry_run] = true
  end
  
  opts.on("-v", "--verbose", "Verbose output") do
    options[:verbose] = true
    options[:quiet] = false  # Verbose overrides quiet
  end
  
  opts.on("-q", "--quiet", "Suppress informational output (errors still shown)") do
    options[:quiet] = true
    options[:verbose] = false  # Quiet overrides verbose
  end
  
  opts.on("--safe", "Disallow downloads to current region (when FLY_REGION is set)") do
    options[:safe] = true
  end

  opts.on("--skip FILE", "Skip databases listed in the specified file") do |file|
    if File.exist?(file)
      options[:skip_list] = File.readlines(file).map do |line|
        # Extract just the database filename from the path
        File.basename(line.strip)
      end.reject(&:empty?)
    else
      puts "Error: Skip file '#{file}' does not exist"
      exit 1
    end
  end

  opts.on("--index-only", "Only sync the index database") do
    options[:only_dbs] += ["index.sqlite3"]
  end

  opts.on("--only DB1,DB2,...", Array, "Only sync the specified databases (comma-separated)") do |list|
    options[:only_dbs] += list.map { |name| File.basename(name.strip, '.sqlite3') + '.sqlite3' }
  end

  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end
end.parse!

# Try to load missing environment variables from rclone config
rclone_config_path = File.expand_path("~/.config/rclone/rclone.conf")
if File.exist?(rclone_config_path)
  rclone_config = File.read(rclone_config_path)
  
  # Parse the showcase section if it exists
  if rclone_config =~ /\[showcase\](.*?)(?:\n\[|\z)/m
    showcase_section = $1
    
    # Extract values from the showcase section
    if ENV["AWS_ACCESS_KEY_ID"].nil? || ENV["AWS_ACCESS_KEY_ID"].empty?
      if showcase_section =~ /^access_key_id\s*=\s*(.+)$/
        ENV["AWS_ACCESS_KEY_ID"] = $1.strip
        puts "Using AWS_ACCESS_KEY_ID from rclone config" if options[:verbose]
      end
    end
    
    if ENV["AWS_SECRET_ACCESS_KEY"].nil? || ENV["AWS_SECRET_ACCESS_KEY"].empty?
      if showcase_section =~ /^secret_access_key\s*=\s*(.+)$/
        ENV["AWS_SECRET_ACCESS_KEY"] = $1.strip
        puts "Using AWS_SECRET_ACCESS_KEY from rclone config" if options[:verbose]
      end
    end
    
    if ENV["AWS_ENDPOINT_URL_S3"].nil? || ENV["AWS_ENDPOINT_URL_S3"].empty?
      if showcase_section =~ /^endpoint\s*=\s*(.+)$/
        ENV["AWS_ENDPOINT_URL_S3"] = $1.strip
        puts "Using AWS_ENDPOINT_URL_S3 from rclone config" if options[:verbose]
      end
    end
  end
end

# Check for S3 environment variables
required_env = ["AWS_SECRET_ACCESS_KEY", "AWS_ACCESS_KEY_ID", "AWS_ENDPOINT_URL_S3"]
missing_env = required_env.select { |var| ENV[var].nil? || ENV[var].empty? }

if !missing_env.empty?
  puts "S3 environment variables not configured, skipping S3 sync" unless options[:quiet]
  exit 0
end

# Load configurations
git_path = File.realpath(File.expand_path('..', __dir__))
ENV["RAILS_DB_VOLUME"] = "/data/db" if Dir.exist? "/data/db"
dbpath = ENV.fetch('RAILS_DB_VOLUME') { "#{git_path}/db" }
require_relative "#{git_path}/lib/showcases_loader"
showcases = ShowcasesLoader.load

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

# Get list of expected database names
expected_databases = tenants.keys.map { |label| "#{label}.sqlite3" }
expected_databases = options[:only_dbs] if options[:only_dbs].any?

# Main sync logic wrapped in error handling
begin
  unless options[:quiet]
    puts "Database Sync with S3"
    puts "=" * 50
    puts "Local path: #{dbpath}"
    puts "S3 endpoint: #{ENV['AWS_ENDPOINT_URL_S3']}"
    puts "Total tenants: #{tenants.size}"
    puts "FLY_REGION: #{ENV['FLY_REGION']}" if ENV['FLY_REGION']
    puts "Dry run: #{options[:dry_run]}" if options[:dry_run]
    puts "Only databases: #{options[:only_dbs].join(', ')}" if options[:only_dbs].any?
    puts "Safe mode: #{options[:safe]} (no downloads to current region)" if options[:safe] && ENV['FLY_REGION']
    puts "Skip list: #{options[:skip_list].size} databases" if options[:skip_list].any?
    puts
  end

# Initialize S3 client with timeouts to prevent hanging
s3_client = Aws::S3::Client.new(
  region: ENV['AWS_REGION'] || 'auto',
  access_key_id: ENV['AWS_ACCESS_KEY_ID'],
  secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
  endpoint: ENV['AWS_ENDPOINT_URL_S3'],
  force_path_style: true,
  http_open_timeout: 15,      # timeout for opening connection
  http_read_timeout: 60,      # timeout for reading response
  http_idle_timeout: 5,       # timeout for idle connections in pool
  http_continue_timeout: 1    # timeout for 100-continue response on uploads
)

# Fix for Tigris hanging on empty Accept-Encoding header
# See: https://github.com/aws/aws-sdk-ruby/issues/2831
class AcceptEncodingHandler < Seahorse::Client::Handler
  def call(context)
    context.http_request.headers['Accept-Encoding'] = 'identity'
    @handler.call(context)
  end
end
s3_client.handlers.add(AcceptEncodingHandler, step: :sign, priority: 99)

# Extract bucket name from endpoint or use default
bucket_name = ENV.fetch('BUCKET_NAME', 'showcase')

# Ensure bucket exists
begin
  s3_client.head_bucket(bucket: bucket_name)
rescue Aws::S3::Errors::NotFound
  puts "Bucket not found: #{bucket_name}"
  exit 1
end

# Load inventories for all regions
# Inventory tracks: db_name => { etag: string, last_modified: timestamp }
inventories = {}
inventory_changed = {}

inventory_path = "#{git_path}/tmp/inventory"
inventory_path = File.expand_path("inventory", File.dirname(dbpath)) if ENV['RAILS_DB_VOLUME']

FileUtils.mkdir_p(inventory_path) unless options[:dry_run]

local_inventories = Dir["#{inventory_path}/*.json"].map { |file| File.basename(file, '.json') }
response = s3_client.list_objects_v2(bucket: bucket_name, prefix: 'inventory/')
if response.contents
  response.contents.each do |object|
    if object.key.end_with?('.json')
      region = File.basename(object.key, '.json')
      inventory_changed[region] = false  # Initialize for each region
      local_cache = "#{inventory_path}/#{region}.json"

      if local_inventories.include?(region) && File.exist?(local_cache) &&
         File.mtime(local_cache).to_i >= object.last_modified.to_i
        inventories[region] = JSON.parse(File.read(local_cache))
      else
        begin
          response = s3_client.get_object(bucket: bucket_name, key: object.key)
          inventories[region] = JSON.parse(response.body.read)
          File.write(local_cache, JSON.pretty_generate(inventories[region])) unless options[:dry_run]
          File.utime(object.last_modified, object.last_modified, local_cache) unless options[:dry_run]
        rescue => e
          puts "Error loading inventory for #{region}: #{e.message}" if options[:verbose]
          inventories[region] = {}
        end
      end

      local_inventories.delete(region)
    end
  end
end

# Initialize missing regions
all_regions = ['index'] + tenant_regions.values.compact.uniq
all_regions.each do |region|
  inventories[region] ||= {}
  inventory_changed[region] ||= false
end

local_inventories.each do |region|
  puts "Removing stale local inventory for #{region}" if options[:verbose]
  File.delete("#{inventory_path}/#{region}.json") unless options[:dry_run]
end

# Helper to get 'date' from database (first event date)
def dbdate(filename, dbpath)
  fullpath = File.expand_path(File.basename(filename, '.sqlite3') + '.sqlite3', dbpath)
  if File.exist?(fullpath)
    begin
      db = SQLite3::Database.new(fullpath)
      result = db.get_first_value("SELECT date FROM events LIMIT 1")
      result
    rescue
      nil
    ensure
      db.close if db
    end
  end
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
        
        # Determine which region owns this database
        tenant_name = filename.sub(/\.sqlite3$/, '')
        owner_region = tenant_regions[tenant_name] || 'index'
        
        # Check the owner region's inventory for matching etag to get actual last_modified time
        actual_last_modified = nil
        if inventories[owner_region] && inventories[owner_region].is_a?(Hash) && 
           inventories[owner_region][filename] && 
           inventories[owner_region][filename]['etag'] == object.etag
          actual_last_modified = Time.parse(inventories[owner_region][filename]['last_modified'])
        else
          obj_response = s3_client.get_object(bucket: bucket_name, key: object.key)
          if obj_response.metadata && obj_response.metadata['last-modified']
            actual_last_modified = Time.parse(obj_response.metadata['last-modified'])
            inventories[owner_region] ||= {}
            inventories[owner_region][filename] = {
              'etag' => obj_response.etag,
              'date' => dbdate(filename, dbpath),
              'last_modified' => actual_last_modified.utc.inspect
            }
            inventory_changed[owner_region] = true
          end
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

puts "S3 objects found: #{s3_objects.size}" unless options[:quiet]
puts unless options[:quiet]

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
    elsif options[:skip_list].include?(db_name) && local_exists
      # Skip download - database is in skip list and exists locally
      skipped << db_name
      puts "Skip download (--skip list): #{db_name}" if options[:verbose]
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
            inventories[owner_region] ||= {}
            inventory_changed[owner_region] ||= false
            inventories[owner_region][db_name] = {
              'etag' => put_response.etag,
              'date' => dbdate(db_name, dbpath),
              'last_modified' => local_mtime.utc.inspect
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
unless options[:quiet]
  puts
  puts "Summary:"
  puts "=" * 50
  puts "Downloads: #{downloads.size}"
  downloads.each do |d|
    puts "  - #{d[:name]}"
  end if !downloads.empty? && options[:verbose]

  puts "Uploads: #{uploads.size}"
  uploads.each do |u|
    puts "  - #{u[:name]}"
  end if !uploads.empty? && options[:verbose]

  puts "Skipped (unchanged): #{skipped.size}" if options[:verbose]
end

# Save updated inventories
unless options[:dry_run]
  inventory_changed.each do |region, changed|
    if changed
      next if ENV['FLY_REGION'] && region != ENV['FLY_REGION'] && region != 'index'

      inventory_key = "inventory/#{region}.json"
      puts "Updating inventory for #{region}" if options[:verbose]

      # Ensure all entries have 'date' field (may be nil)
      inventories[region].each do |database, info|
        if !info.has_key?('date')
          info['date'] = dbdate(database, dbpath)
        end
      end

      inventory_data = JSON.pretty_generate(inventories[region])
      
      begin
        response = s3_client.put_object(
          bucket: bucket_name,
          key: inventory_key,
          body: inventory_data,
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

# Upload map ERB files if index was uploaded
# Maps are only uploaded from Rubix (admin server), not from Fly.io regions
if !options[:dry_run] && uploads.any? { |u| u[:name] == 'index.sqlite3' } && !ENV['FLY_REGION']
  puts "Uploading map ERB files..." unless options[:quiet]

  require_relative "#{git_path}/lib/map_downloader"

  map_uploads = []
  MapDownloader::MAP_FILES.each do |map_name|
    local_path = File.join(git_path, 'app/views/event', "#{map_name}.html.erb")
    s3_key = "views/event/#{map_name}.html.erb"

    if File.exist?(local_path)
      begin
        local_mtime = File.mtime(local_path)
        File.open(local_path, 'rb') do |file|
          s3_client.put_object(
            bucket: bucket_name,
            key: s3_key,
            body: file,
            content_type: 'text/html',
            metadata: {
              'last-modified' => local_mtime.utc.iso8601
            }
          )
        end
        map_uploads << map_name
        puts "  Uploaded: #{map_name}.html.erb" if options[:verbose]
      rescue => e
        puts "  Error uploading #{map_name}.html.erb: #{e.message}"
        if ENV["SENTRY_DSN"]
          Sentry.capture_message("Error uploading map #{map_name}: #{e.message}", level: :error)
        end
      end
    else
      puts "  Missing: #{map_name}.html.erb" if options[:verbose]
    end
  end

  puts "Map uploads: #{map_uploads.size}" unless options[:quiet]
end

# Call webhook if something was uploaded
if !options[:dry_run] && uploads.size > 0
  begin
    hostenv = `env | grep FLY` if ENV['FLY_REGION']

    uri = URI('https://rubix.intertwingly.net/webhook/showcase')
    res = Net::HTTP.get_response(uri)
    if res.is_a?(Net::HTTPSuccess)
      puts res.body unless options[:quiet]
    else
      STDERR.puts res unless options[:quiet]
      STDERR.puts res.body unless options[:quiet]
      if ENV["SENTRY_DSN"]
        Sentry.capture_message("webhook failure:\n\n#{hostenv}\n#{res.body}")
      end
    end
  rescue => e
    error_msg = "Error calling webhook: #{e.message}"
    puts error_msg unless options[:quiet]
    if ENV["SENTRY_DSN"]
      Sentry.capture_exception(e, extra: {
        operation: 'webhook',
        uploads_count: uploads.size
      })
    end
  end
end

unless options[:quiet]
  puts
  puts "Sync complete#{options[:dry_run] ? ' (dry run - no changes made)' : ''}."
end

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
