#!/usr/bin/env ruby
# frozen_string_literal: true

# Render both ERB and JavaScript-converted versions for comparison
#
# Usage:
#   scripts/render_erb_and_js.rb DATABASE judge_id heat_number [style]
#
# Examples:
#   scripts/render_erb_and_js.rb db/2025-barcelona-november.sqlite3 83 123 radio

require 'pathname'
require 'json'
require 'tempfile'

# Parse arguments
database = nil
if ARGV.first && !ARGV.first.start_with?('-') && !ARGV.first.match?(/^\d+$/)
  database = ARGV.shift
elsif ENV['RAILS_APP_DB']
  database = ENV['RAILS_APP_DB']
end

if database.nil? || ARGV.length < 2
  puts "Usage: #{$0} DATABASE judge_id heat_number [style]"
  puts "   or: RAILS_APP_DB=database #{$0} judge_id heat_number [style]"
  puts ""
  puts "Examples:"
  puts "  #{$0} db/2025-barcelona-november.sqlite3 83 123 radio"
  puts "  RAILS_APP_DB=2025-barcelona-november #{$0} 83 123"
  exit 1
end

judge_id = ARGV[0]
heat_number = ARGV[1]
style = ARGV[2] || 'radio'

# Set up Rails environment
script_dir = Pathname.new(__FILE__).dirname.realpath
rails_root = script_dir.parent
Dir.chdir(rails_root)

# Extract database name from path
db_name = File.basename(database, '.sqlite3')
ENV['RAILS_APP_DB'] = db_name
ENV['RAILS_STORAGE'] = File.join(rails_root, 'storage')

# Load Rails environment
require File.expand_path('config/environment', rails_root)

puts "="*80
puts "Rendering ERB version..."
puts "="*80

# Render ERB version
erb_env = {
  "PATH_INFO" => "/scores/#{judge_id}/heat/#{heat_number}",
  "REQUEST_METHOD" => "GET",
  "QUERY_STRING" => "style=#{style}"
}

code, headers, response = Rails.application.routes.call(erb_env)
if code != 200
  puts "Error: HTTP #{code}"
  exit 1
end

erb_html = response.body.force_encoding('utf-8')
erb_file = "/tmp/erb_rendered.html"
File.write(erb_file, erb_html)
erb_rows = erb_html.scan(/<tr/).length

puts "✓ ERB rendered: #{erb_html.length} bytes, #{erb_rows} <tr> tags"
puts "  Saved to: #{erb_file}"

puts ""
puts "="*80
puts "Rendering JavaScript version..."
puts "="*80

# Fetch the converted JavaScript templates
js_env = {
  "PATH_INFO" => "/templates/scoring.js",
  "REQUEST_METHOD" => "GET"
}

code, headers, response = Rails.application.routes.call(js_env)
if code != 200
  puts "Error fetching templates: HTTP #{code}"
  exit 1
end

js_code = response.body.force_encoding('utf-8')

# Fetch normalized data from /scores/:judge/heats/data (same as SPA uses)
data_env = {
  "PATH_INFO" => "/scores/#{judge_id}/heats/data",
  "REQUEST_METHOD" => "GET",
  "QUERY_STRING" => "style=#{style}"
}

code, headers, response = Rails.application.routes.call(data_env)
if code != 200
  puts "Error fetching normalized data: HTTP #{code}"
  exit 1
end

normalized_json = response.body.force_encoding('utf-8')
normalized_data = JSON.parse(normalized_json)

puts "Loaded #{normalized_data['heats'].length} heats for #{normalized_data['judge']['display_name']}"

# Transform using HeatDataAdapter (matches production SPA code)
# We'll use the standalone hydration script to transform the data
# Redirect stderr to /dev/null to get clean JSON on stdout
hydration_result = `node scripts/hydrate_heats.mjs #{judge_id} #{style} #{database} 2>/dev/null`
unless $?.success?
  puts "Error running hydration script (exit code: #{$?.exitstatus})"
  exit 1
end

# Find the specific heat we want
all_hydrated = JSON.parse(hydration_result)
heat_data = all_hydrated['heats'].find { |h| h['number'] == heat_number.to_f }

unless heat_data
  puts "Error: Heat #{heat_number} not found in hydrated data"
  exit 1
end

puts "Transformed heat #{heat_number} for rendering"

# Write JavaScript code to temp file
js_file = Tempfile.new(['template', '.mjs'])
begin
  # Strip export keywords
  regular_code = js_code.gsub(/^export /m, '')

  js_file.write(<<~JAVASCRIPT)
    #{regular_code}

    // Data from hydration (normalized → denormalized transformation)
    // This matches what HeatDataAdapter does in production SPA code
    const data = #{heat_data.to_json};

    // Render using the main heat template
    const html = heat(data);
    console.log(html);
  JAVASCRIPT

  js_file.close

  # Execute the JavaScript with Node.js
  js_html = `node #{js_file.path} 2>&1`

  if $?.success?
    js_output_file = "/tmp/js_rendered.html"
    File.write(js_output_file, js_html)
    js_rows = js_html.scan(/<tr/).length

    puts "✓ JS rendered: #{js_html.length} bytes, #{js_rows} <tr> tags"
    puts "  Saved to: #{js_output_file}"
  else
    puts "Error executing JavaScript:"
    puts js_html
    exit 1
  end

ensure
  js_file.unlink
end

puts ""
puts "="*80
puts "Comparison Summary"
puts "="*80
puts "ERB: #{erb_rows} rows, #{erb_html.length} bytes"
puts "JS:  #{js_rows} rows, #{js_html.length} bytes"

if erb_rows == js_rows
  puts "✓ Row counts match!"
else
  puts "✗ Row count mismatch: ERB has #{erb_rows}, JS has #{js_rows}"
end

puts ""
puts "Files saved to /tmp/ for comparison:"
puts "  /tmp/erb_rendered.html"
puts "  /tmp/js_rendered.html"
