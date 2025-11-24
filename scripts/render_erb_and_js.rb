#!/usr/bin/env ruby
# frozen_string_literal: true

# Render both ERB and JavaScript-converted versions for comparison
#
# Usage:
#   scripts/render_erb_and_js.rb DATABASE judge_id [heat_number] [style]
#
# Examples:
#   # Heat list
#   scripts/render_erb_and_js.rb db/2025-barcelona-november.sqlite3 83
#   RAILS_APP_DB=2025-barcelona-november scripts/render_erb_and_js.rb 83
#
#   # Individual heat
#   scripts/render_erb_and_js.rb db/2025-barcelona-november.sqlite3 83 123 radio
#   RAILS_APP_DB=2025-barcelona-november scripts/render_erb_and_js.rb 83 123

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

if database.nil? || ARGV.length < 1
  puts "Usage: #{$0} DATABASE judge_id [heat_number] [style]"
  puts "   or: RAILS_APP_DB=database #{$0} judge_id [heat_number] [style]"
  puts ""
  puts "Examples:"
  puts "  Heat list:"
  puts "    #{$0} db/2025-barcelona-november.sqlite3 83"
  puts "    RAILS_APP_DB=2025-barcelona-november #{$0} 83"
  puts ""
  puts "  Individual heat:"
  puts "    #{$0} db/2025-barcelona-november.sqlite3 83 123 radio"
  puts "    RAILS_APP_DB=2025-barcelona-november #{$0} 83 123"
  exit 1
end

judge_id = ARGV[0]
heat_number = ARGV[1]  # nil for heat list
style = ARGV[2] || 'radio'

# Determine if we're rendering a heat list or individual heat
is_heat_list = heat_number.nil?

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
puts is_heat_list ? "Rendering Heat List ERB version..." : "Rendering Individual Heat ERB version..."
puts "="*80

# Render ERB version
erb_path = if is_heat_list
  "/scores/#{judge_id}/heatlist"
else
  "/scores/#{judge_id}/heat/#{heat_number}"
end

erb_env = {
  "PATH_INFO" => erb_path,
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

# Save templates for debugging
templates_file = "/tmp/scoring_templates.js"
File.write(templates_file, js_code)
puts "✓ Templates fetched: #{js_code.length} bytes"
puts "  Saved to: #{templates_file}"

# Fetch bulk data from the SPA endpoint (what the actual SPA uses)
heats_data_env = {
  "PATH_INFO" => "/scores/#{judge_id}/heats/data",
  "REQUEST_METHOD" => "GET",
  "HTTP_ACCEPT" => "application/json"
}

code, headers, response = Rails.application.routes.call(heats_data_env)
if code != 200
  puts "Error fetching heats data: HTTP #{code}"
  exit 1
end

heats_json = response.body.force_encoding('utf-8')
all_data = JSON.parse(heats_json)

# Save the normalized data to a temp file
heats_data_file = "/tmp/heats_data.json"
File.write(heats_data_file, heats_json)
puts "✓ Bulk data fetched: #{heats_json.length} bytes (#{all_data['heats'].length} heats)"
puts "  Saved to: #{heats_data_file}"

if is_heat_list
  # For heat list, we don't need hydration - just use the bulk data directly
  template_data = all_data

  # Save template data for debugging
  template_data_file = "/tmp/js_template_data.json"
  File.write(template_data_file, JSON.pretty_generate(template_data))

  puts "✓ Using bulk data directly for heat list"
  puts "  Saved template data to: #{template_data_file}"
else
  # For individual heat, use the hydration script
  hydrate_script = File.join(rails_root, 'scripts', 'hydrate_heats.mjs')

  # Capture only stdout (not stderr) to avoid Node.js warnings polluting JSON
  hydrated_json = `node #{hydrate_script} #{judge_id} #{heat_number} #{style} #{heats_data_file}`

  if $?.success?
    # The hydration script returns complete template data
    template_data = JSON.parse(hydrated_json)

    # Save template data for debugging
    template_data_file = "/tmp/js_template_data.json"
    File.write(template_data_file, JSON.pretty_generate(template_data))

    puts "✓ Heat #{heat_number} hydrated with #{template_data['subjects'].length} subjects"
    puts "  Saved template data to: #{template_data_file}"
  else
    puts "Error hydrating heat data:"
    # Show error output
    error_output = `node #{hydrate_script} #{judge_id} #{heat_number} #{style} #{heats_data_file} 2>&1`
    puts error_output
    exit 1
  end
end

# Write JavaScript code to temp file
js_file = Tempfile.new(['template', '.mjs'])
begin
  # Strip export keywords
  regular_code = js_code.gsub(/^export /m, '')

  if is_heat_list
    # Render heat list
    js_file.write(<<~JAVASCRIPT)
      #{regular_code}

      // Data from heats/data endpoint
      const rawData = #{template_data.to_json};

      // Group heats by number (matching ERB .group(:number) and Stimulus controller behavior)
      const heatsByNumber = {};
      rawData.heats.forEach(heat => {
        if (!heatsByNumber[heat.number]) {
          heatsByNumber[heat.number] = heat;
        }
      });
      const data = { ...rawData, heats: Object.values(heatsByNumber) };

      // Render using the heat list template
      const html = heatlist(data);
      console.log(html);
    JAVASCRIPT
  else
    # Render individual heat
    js_file.write(<<~JAVASCRIPT)
      #{regular_code}

      // Data from per-heat endpoint (same as ERB uses)
      const data = #{template_data.to_json};

      // Render using the main heat template
      const html = heat(data);
      console.log(html);
    JAVASCRIPT
  end

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
puts "Files saved to /tmp/ for analysis:"
puts ""
puts "  HTML outputs:"
puts "    /tmp/erb_rendered.html         - ERB template output"
puts "    /tmp/js_rendered.html          - JavaScript template output"
puts ""
puts "  JavaScript (for debugging):"
puts "    /tmp/scoring_templates.js      - Converted templates from /templates/scoring.js"
puts ""
puts "  JSON data (for debugging):"
puts "    /tmp/heats_data.json           - Raw normalized data from /heats/data endpoint"
if is_heat_list
  puts "    /tmp/js_template_data.json     - Bulk data used for heat list rendering"
else
  puts "    /tmp/js_template_data.json     - Complete template data (after buildHeatTemplateData)"
end
