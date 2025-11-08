#!/usr/bin/env ruby
# frozen_string_literal: true

# Render Rails pages without starting a server
#
# Usage:
#   .claude/skills/render-page/scripts/render.rb DATABASE [options] PATH [PATH...]
#
# Arguments:
#   DATABASE          Database file (e.g., db/2025-boston.sqlite3) or 'test' or 'demo'
#
# Options:
#   --check           Only check if page renders (exit 0 on success, 1 on failure)
#   --html            Output full HTML content
#   --search TEXT     Search for specific text in rendered output
#   --verbose, -v     Show detailed information
#   --help, -h        Show this help message
#
# Examples:
#   # Check if a page renders successfully
#   .claude/skills/render-page/scripts/render.rb db/2025-boston.sqlite3 --check /heats
#
#   # Get full HTML output
#   .claude/skills/render-page/scripts/render.rb db/2025-boston.sqlite3 --html /people
#
#   # Search for specific content
#   .claude/skills/render-page/scripts/render.rb db/2025-boston.sqlite3 --search "Students" /people
#
#   # Test multiple pages
#   .claude/skills/render-page/scripts/render.rb db/2025-boston.sqlite3 /people /heats /solos

require 'optparse'
require 'pathname'

# Show help if --help is requested without database
if ARGV.include?('--help') || ARGV.include?('-h')
  puts "Usage: #{$0} DATABASE [options] PATH [PATH...]"
  puts "   or: RAILS_APP_DB=database #{$0} [options] PATH [PATH...]"
  puts ""
  puts "Render Rails pages without starting a server"
  puts ""
  puts "Arguments:"
  puts "  DATABASE          Database file (e.g., db/2025-boston.sqlite3) or name (2025-boston)"
  puts "                    Can also be 'test' or 'demo'"
  puts "                    Alternative: Set RAILS_APP_DB environment variable"
  puts ""
  puts "Options:"
  puts "  --check           Only check if page renders (exit 0 on success, 1 on failure)"
  puts "  --html            Output full HTML content"
  puts "  --search TEXT     Search for specific text in rendered output"
  puts "  -v, --verbose     Show detailed information"
  puts "  -h, --help        Show this help message"
  puts ""
  puts "Examples:"
  puts "  #{$0} db/2025-boston.sqlite3 --check /heats"
  puts "  #{$0} 2025-boston --html /people"
  puts "  RAILS_APP_DB=2025-boston #{$0} --search 'Solos' /solos"
  exit 0
end

# Get the database - either from argument or environment variable
database = nil

# Check if first argument looks like a database path/name (not an option or path)
if ARGV.first && !ARGV.first.start_with?('--') && !ARGV.first.start_with?('-') && !ARGV.first.start_with?('/')
  database = ARGV.shift
elsif ENV['RAILS_APP_DB']
  database = ENV['RAILS_APP_DB']
end

if database.nil?
  puts "Error: DATABASE argument required (or set RAILS_APP_DB environment variable)"
  puts "Usage: #{$0} DATABASE [options] PATH [PATH...]"
  puts "   or: RAILS_APP_DB=database #{$0} [options] PATH [PATH...]"
  puts "Use --help for more information"
  exit 1
end

# Set up Rails environment based on database
script_dir = Pathname.new(__FILE__).dirname.realpath
# Go up from scripts -> render-page -> skills -> .claude -> showcase
rails_root = script_dir.parent.parent.parent.parent
Dir.chdir(rails_root)

# Extract database name from path (handles both "db/name.sqlite3" and just "name")
db_name = File.basename(database, '.sqlite3')
ENV['RAILS_APP_DB'] = db_name
ENV['RAILS_STORAGE'] = File.join(rails_root, 'storage')

# Handle test environment
if database == 'test'
  ENV['RAILS_ENV'] = 'test'
end

# Load Rails environment
require File.expand_path('config/environment', rails_root)

# Prepare test database if needed
if database == 'test'
  require 'rake'
  Rails.application.load_tasks
  Rake::Task['db:prepare'].invoke
  Rake::Task['db:fixtures:load'].invoke
end

# Parse command-line options
options = {
  check: false,
  html: false,
  search: nil,
  verbose: false
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} DATABASE [options] PATH [PATH...]"
  opts.separator ""
  opts.separator "Render Rails pages without starting a server"
  opts.separator ""
  opts.separator "Options:"

  opts.on("--check", "Only check if page renders (exit 0 on success, 1 on failure)") do
    options[:check] = true
  end

  opts.on("--html", "Output full HTML content") do
    options[:html] = true
  end

  opts.on("--search TEXT", "Search for specific text in rendered output") do |text|
    options[:search] = text
  end

  opts.on("-v", "--verbose", "Show detailed information") do
    options[:verbose] = true
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end

begin
  parser.parse!
rescue OptionParser::InvalidOption => e
  puts "Error: #{e.message}"
  puts parser
  exit 1
end

if ARGV.empty?
  puts "Error: No paths specified"
  puts parser
  exit 1
end

paths = ARGV

# Track results
results = []
exit_code = 0

# Render each path
paths.each do |path|
  env = {
    "PATH_INFO" => path,
    "REQUEST_METHOD" => "GET"
  }

  begin
    code, headers, response = Rails.application.routes.call(env)

    result = {
      path: path,
      code: code,
      success: code == 200,
      response: response
    }

    if code == 200
      html = response.body.force_encoding('utf-8')
      result[:html] = html
      result[:size] = html.length

      # Search for specific content if requested
      if options[:search]
        result[:found] = html.include?(options[:search])
      end
    end

    results << result

  rescue => e
    result = {
      path: path,
      success: false,
      error: e.message
    }
    results << result
    exit_code = 1
  end
end

# Output results based on mode
if options[:html]
  # HTML mode - output raw HTML (only works for single path)
  if paths.length == 1 && results.first[:success]
    puts results.first[:html]
  elsif paths.length > 1
    puts "Error: --html mode only works with a single path"
    exit 1
  else
    puts "Error: Page failed to render"
    exit 1
  end

elsif options[:check]
  # Check mode - silent unless verbose, exit code indicates success
  if options[:verbose]
    results.each do |result|
      if result[:success]
        puts "✓ #{result[:path]}"
      elsif result[:error]
        puts "✗ #{result[:path]} - Error: #{result[:error]}"
      else
        puts "✗ #{result[:path]} - HTTP #{result[:code]}"
      end
    end
  end

  # Set exit code
  exit_code = results.all? { |r| r[:success] } ? 0 : 1

elsif options[:search]
  # Search mode - report if content was found
  results.each do |result|
    if result[:success]
      if result[:found]
        puts "✓ #{result[:path]} - '#{options[:search]}' found"
      else
        puts "✗ #{result[:path]} - '#{options[:search]}' not found"
        exit_code = 1
      end
    elsif result[:error]
      puts "✗ #{result[:path]} - Error: #{result[:error]}"
      exit_code = 1
    else
      puts "✗ #{result[:path]} - HTTP #{result[:code]}"
      exit_code = 1
    end
  end

else
  # Default mode - show summary
  results.each do |result|
    if result[:success]
      size_kb = (result[:size] / 1024.0).round(1)
      puts "✓ #{result[:path]} - #{result[:size]} bytes (#{size_kb} KB)"

      if options[:verbose]
        puts "  Response headers:"
        result[:response].each do |key, value|
          puts "    #{key}: #{value}"
        end
      end
    elsif result[:error]
      puts "✗ #{result[:path]} - Error: #{result[:error]}"
      exit_code = 1
    else
      puts "✗ #{result[:path]} - HTTP #{result[:code]}"
      exit_code = 1
    end
  end
end

exit exit_code
