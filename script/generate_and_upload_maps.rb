#!/usr/bin/env ruby
# Generate map ERB files and upload to S3
# This script:
# 1. Generates tmp/map.yml from index.sqlite3 (location data)
# 2. Runs makemaps.js to add x,y coordinates and generate ERB files
# 3. Uploads to S3 via sync_databases_s3.rb (which handles webhook)
#
# Called by:
# - script/config-update (before syncing index.sqlite3)
# - Admin controllers after location/region changes

require 'bundler/setup'
require 'yaml'
require 'fileutils'
require 'open3'

# Load configuration
git_path = File.realpath(File.expand_path('..', __dir__))
ENV["RAILS_DB_VOLUME"] = "/data/db" if Dir.exist? "/data/db"
dbpath = ENV.fetch('RAILS_DB_VOLUME') { "#{git_path}/db" }
index_db = File.join(dbpath, 'index.sqlite3')

puts "Generating and uploading map files..."
puts "=" * 70

unless File.exist?(index_db)
  puts "ERROR: index.sqlite3 not found at #{index_db}"
  exit 1
end

# Ensure tmp directory exists
FileUtils.mkdir_p("#{git_path}/tmp")

# Step 1: Generate map data from database
puts "\nStep 1: Generating map.yml from index.sqlite3..."
puts "-" * 70

# Set database environment and load Rails
ENV['DATABASE_URL'] = "sqlite3:#{index_db}"
require_relative '../config/environment'
require_relative '../lib/region_configuration'

# Generate map data using shared module
map_data = RegionConfiguration.generate_map_data

puts "   Found #{map_data['regions']&.size || 0} deployed regions"
puts "   Found #{map_data['studios']&.size || 0} studio locations"

# Write YAML to tmp directory
map_yml_path = File.join(git_path, 'tmp/map.yml')
new_map_yaml = YAML.dump(map_data)

# Check if map data actually changed (Layer 1 optimization)
if File.exist?(map_yml_path)
  old_map_yaml = File.read(map_yml_path)
  if old_map_yaml == new_map_yaml
    puts "   Map data unchanged, skipping generation"
    puts "\n" + "=" * 70
    puts "SUCCESS: No map changes detected"
    puts "=" * 70
    exit 0
  end
end

File.write(map_yml_path, new_map_yaml)
puts "   Map data changed, wrote tmp/map.yml"

# Step 2: Run makemaps.js to add x,y coordinates
puts "\nStep 2: Running makemaps.js to add x,y coordinates..."
puts "-" * 70

# Run makemaps.js (reads/writes tmp/map.yml per utils/mapper/files.yml)
Dir.chdir(git_path) do
  stdout, stderr, status = Open3.capture3('node', 'utils/mapper/makemaps.js')
  puts stdout unless stdout.empty?
  $stderr.puts stderr unless stderr.empty?

  unless status.success?
    puts "ERROR: makemaps.js failed with exit code #{status.exitstatus}"
    exit 1
  end
end

puts "   makemaps.js completed successfully"

# Step 3: Verify ERB files were generated
puts "\nStep 3: Verifying generated ERB files..."
puts "-" * 70

require_relative '../lib/map_downloader'

generated = []
missing = []
MapDownloader::MAP_FILES.each do |map_name|
  path = File.join(git_path, 'app/views/event', "#{map_name}.html.erb")
  if File.exist?(path)
    generated << map_name
    puts "   #{map_name}.html.erb - OK"
  else
    missing << map_name
    puts "   #{map_name}.html.erb - MISSING"
  end
end

if missing.any?
  puts "\nWARNING: #{missing.length} map file(s) missing"
end

puts "\n" + "=" * 70
puts "SUCCESS: Generated #{generated.length} map file(s)"
puts ""
puts "Maps will be uploaded when sync_databases_s3.rb runs"
puts "(it uploads maps when index.sqlite3 is uploaded)"
puts "=" * 70
