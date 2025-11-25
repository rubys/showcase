#!/usr/bin/env ruby
# frozen_string_literal: true

# Render JavaScript-converted ERB templates with actual data (no server needed)
#
# Usage:
#   scripts/render_js_template.rb DATABASE judge_id heat_number [style]
#
# Examples:
#   scripts/render_js_template.rb db/2025-barcelona-november.sqlite3 83 123 radio
#   RAILS_APP_DB=2025-barcelona-november scripts/render_js_template.rb 83 123 radio

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
  puts "  RAILS_APP_DB=2025-barcelona-november #{$0} 83 123 radio"
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

# Fetch the converted JavaScript templates
$stderr.puts "Fetching converted templates..."
env = {
  "PATH_INFO" => "/templates/scoring.js",
  "REQUEST_METHOD" => "GET"
}

code, headers, response = Rails.application.routes.call(env)
if code != 200
  $stderr.puts "Error fetching templates: HTTP #{code}"
  exit 1
end

js_code = response.body.force_encoding('utf-8')

# Fetch the heat data JSON
$stderr.puts "Fetching heat data (judge: #{judge_id}, heat: #{heat_number}, style: #{style})..."
env = {
  "PATH_INFO" => "/scores/#{judge_id}/heats/#{heat_number}",
  "REQUEST_METHOD" => "GET",
  "QUERY_STRING" => "style=#{style}"
}

code, headers, response = Rails.application.routes.call(env)
if code != 200
  $stderr.puts "Error fetching heat data: HTTP #{code}"
  exit 1
end

json_data = response.body.force_encoding('utf-8')
data = JSON.parse(json_data)

# Write JavaScript code to temp file
js_file = Tempfile.new(['template', '.mjs'])
begin
  # Strip export keywords
  regular_code = js_code.gsub(/^export /m, '')

  js_file.write(<<~JAVASCRIPT)
    #{regular_code}

    // Select appropriate template based on data
    const data = #{data.to_json};

    let templateFn;
    if (data.heat.category === 'Solo') {
      templateFn = soloHeat;
    } else if (data.final) {
      templateFn = rankHeat;
    } else if (data.style !== 'cards' || !data.scores || data.scores.length === 0) {
      templateFn = tableHeat;
    } else {
      templateFn = cardsHeat;
    }

    // Render and output
    const html = templateFn(data);
    console.log(html);
  JAVASCRIPT

  js_file.close

  # Execute the JavaScript with Node.js
  $stderr.puts "Rendering template with Node.js..."
  output = `node #{js_file.path} 2>&1`

  if $?.success?
    puts output
    $stderr.puts "\nRendering complete! (#{output.length} bytes)"
  else
    $stderr.puts "Error executing JavaScript:"
    $stderr.puts output
    exit 1
  end

ensure
  js_file.unlink
end
