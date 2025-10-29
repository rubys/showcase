#!/usr/bin/env ruby

require 'yaml'
require 'fileutils'
require 'optparse'

# Parse command line arguments
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"
  
  opts.on("--symlink", "Check for symlinks pointing to databases") do
    options[:symlink] = true
  end
  
  opts.on("--prune DAYS", Integer, "Remove orphan databases older than DAYS") do |days|
    options[:prune] = days
  end
  
  opts.on("--quiet", "Suppress orphan database listing") do
    options[:quiet] = true
  end
  
  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end
end.parse!

# Load configurations
git_path = File.realpath(File.expand_path('..', __dir__))
ENV["RAILS_DB_VOLUME"]= "/data/db" if Dir.exist? "/data/db"
dbpath = ENV.fetch('RAILS_DB_VOLUME') { "#{git_path}/db" }
require_relative "#{git_path}/lib/showcases_loader"
showcases = ShowcasesLoader.load

# Build tenant hash from nginx-config.rb logic
# Hash format: { label => name }
tenants = {}

# Add index tenant
tenants["index"] = "index"

# Process showcases to build tenant list
showcases.each do |year, list|
  list.each do |token, info|
    if info[:events]
      info[:events].each do |subtoken, subinfo|
        label = "#{year}-#{token}-#{subtoken}"
        name = info[:name] + ' - ' + subinfo[:name]
        tenants[label] = name
      end
    else
      label = "#{year}-#{token}"
      name = info[:name]
      tenants[label] = name
    end
  end
end

# Add demo tenant if running in a region
if ENV['FLY_REGION'] || ENV['KAMAL_CONTAINER_NAME']
  tenants["demo"] = "Demo"
end

# Get list of expected database names
expected_databases = tenants.keys.map { |label| "#{label}.sqlite3" }

# Get list of actual SQLite databases in dbpath
actual_databases = Dir.glob("#{dbpath}/*.sqlite3").map { |path| File.basename(path) }

# Find all symlinks and their targets
symlink_targets = []
Dir.glob("#{dbpath}/*.sqlite3").each do |path|
  if File.symlink?(path)
    target = File.readlink(path)
    # Handle both absolute and relative symlink targets
    if target.start_with?('/')
      symlink_targets << File.basename(target)
    else
      symlink_targets << target
    end
  end
end

# Find orphaned databases (exist on disk but not in tenant list, excluding symlink targets)
orphaned = actual_databases - expected_databases - symlink_targets

# Find missing databases (in tenant list but don't exist)
missing = expected_databases - actual_databases

# Report results
puts "Database Path: #{dbpath}"
puts "Total Tenants: #{tenants.size}"
puts "Total Database Files: #{actual_databases.length}"
puts "Symlink Targets Excluded: #{symlink_targets.length}"
puts

if orphaned.empty?
  puts "✓ No orphaned databases found (excluding symlink targets)"
else
  if !options[:quiet]
    puts "Orphaned Databases (#{orphaned.length}):"
    puts "These databases exist on disk but are not in the tenant list (symlink targets excluded):"
  end
  
  # Track databases to prune if option is set
  databases_to_prune = []
  
  orphaned.sort.each do |db|
    file_path = "#{dbpath}/#{db}"
    size = File.size(file_path)
    mtime = File.mtime(file_path)
    age_days = (Time.now - mtime) / 86400
    
    if !options[:quiet]
      puts "  - #{db} (#{(size / 1024.0 / 1024.0).round(2)} MB, modified: #{mtime.strftime('%Y-%m-%d %H:%M')})"
    end
    
    # Check if database should be pruned
    if options[:prune] && age_days > options[:prune]
      databases_to_prune << {path: file_path, name: db, age_days: age_days.round(1)}
    end
  end
  
  # Prune old orphan databases if requested
  if options[:prune] && !databases_to_prune.empty?
    puts
    puts "Pruning #{databases_to_prune.length} orphan databases older than #{options[:prune]} days:"
    databases_to_prune.each do |db_info|
      puts "  Removing #{db_info[:name]} (#{db_info[:age_days]} days old)..."
      File.delete(db_info[:path])
      puts "    ✓ Deleted"
    end
  elsif options[:prune]
    puts
    puts "✓ No orphan databases older than #{options[:prune]} days to prune"
  end
end

puts

if missing.empty?
  puts "✓ No missing databases"
else
  puts "Missing Databases (#{missing.length}):"
  puts "These databases are in the tenant list but don't exist on disk:"
  missing.sort.each do |db|
    label = File.basename(db, '.sqlite3')
    tenant_name = tenants[label]
    puts "  - #{db} (#{tenant_name})"
  end
end

# Check for symlinks pointing to databases
if options[:symlink]
  puts
  puts "Checking for database symlinks..."
  symlinks = Dir.glob("#{dbpath}/*.sqlite3").select { |path| File.symlink?(path) }
  if symlinks.empty?
    puts "✓ No database symlinks found"
  else
    puts "Database Symlinks (#{symlinks.length}):"
    symlinks.each do |symlink|
      target = File.readlink(symlink)
      basename = File.basename(symlink)
      puts "  - #{basename} -> #{target}"
    end
  end
end
