#!/usr/bin/env ruby
# Compare per-heat endpoint data vs hydrated data for the same heat
# Usage: bin/run db/DATABASE.sqlite3 scripts/compare_heat_data.rb judge_id heat_number [style]

require 'json'

judge_id = ARGV[0]&.to_i
heat_number = ARGV[1]&.to_f
style = ARGV[2] || 'radio'

if judge_id.nil? || judge_id == 0 || heat_number.nil?
  STDERR.puts "Usage: bin/run DATABASE scripts/compare_heat_data.rb judge_id heat_number [style]"
  exit 1
end

# Fetch per-heat endpoint data (known to work)
per_heat_env = {
  "PATH_INFO" => "/scores/#{judge_id}/heats/#{heat_number}",
  "REQUEST_METHOD" => "GET",
  "QUERY_STRING" => "style=#{style}"
}

code, headers, response = Rails.application.routes.call(per_heat_env)
if code != 200
  STDERR.puts "Error fetching per-heat data: HTTP #{code}"
  exit 1
end

per_heat_data = JSON.parse(response.body.force_encoding('utf-8'))

# Save per-heat data to /tmp
per_heat_path = "/tmp/per_heat_#{judge_id}_#{heat_number}.json"
File.write(per_heat_path, JSON.pretty_generate(per_heat_data))

STDERR.puts "Per-heat endpoint: #{per_heat_data['subjects'].length} subjects"

# Now call the Node.js hydration script (redirect stderr to not interfere with JSON parsing)
hydration_result = `node scripts/hydrate_heats.mjs #{judge_id} #{style} #{ENV['RAILS_APP_DB']} 2>/dev/null`
if $?.exitstatus != 0
  STDERR.puts "Hydration script failed with exit code #{$?.exitstatus}"
  exit 1
end

# Extract just the heat we want from hydrated data
all_hydrated = JSON.parse(hydration_result)
hydrated_heat = all_hydrated['heats'].find { |h| h['number'] == heat_number }

if hydrated_heat.nil?
  STDERR.puts "Heat #{heat_number} not found in hydrated data"
  exit 1
end

# Save hydrated data to /tmp
hydrated_path = "/tmp/hydrated_#{judge_id}_#{heat_number}.json"
File.write(hydrated_path, JSON.pretty_generate(hydrated_heat))

STDERR.puts "Hydrated data: #{hydrated_heat['subjects'].length} subjects"
STDERR.puts ""
STDERR.puts "Comparing data structures..."
STDERR.puts "Files saved for manual inspection:"
STDERR.puts "  Per-heat: #{per_heat_path}"
STDERR.puts "  Hydrated: #{hydrated_path}"
STDERR.puts ""

# Compare key fields
def compare_field(name, per_heat_val, hydrated_val)
  if per_heat_val == hydrated_val
    puts "✓ #{name}: matches"
  else
    puts "✗ #{name}: DIFFERENT"
    puts "  Per-heat: #{per_heat_val.inspect}"
    puts "  Hydrated: #{hydrated_val.inspect}"
  end
end

compare_field("number", per_heat_data['number'], hydrated_heat['number'])
compare_field("style", per_heat_data['style'], hydrated_heat['style'])
compare_field("dance", per_heat_data['dance'], hydrated_heat['dance'])
compare_field("subjects.length", per_heat_data['subjects'].length, hydrated_heat['subjects'].length)

puts ""
puts "Top-level fields:"
compare_field("event.id", per_heat_data['event']&.[]('id'), hydrated_heat['event']&.[]('id'))
compare_field("event.name", per_heat_data['event']&.[]('name'), hydrated_heat['event']&.[]('name'))
compare_field("event.student_judge_assignments", per_heat_data['event']&.[]('student_judge_assignments'), hydrated_heat['event']&.[]('student_judge_assignments'))
compare_field("judge.id", per_heat_data['judge']&.[]('id'), hydrated_heat['judge']&.[]('id'))
compare_field("judge.display_name", per_heat_data['judge']&.[]('display_name'), hydrated_heat['judge']&.[]('display_name'))
compare_field("judge_present", per_heat_data['judge_present'], hydrated_heat['judge_present'])
compare_field("feedbacks.length", per_heat_data['feedbacks']&.length || 0, hydrated_heat['feedbacks']&.length || 0)
compare_field("assign_judges", per_heat_data['assign_judges'], hydrated_heat['assign_judges'])
compare_field("show", per_heat_data['show'], hydrated_heat['show'])
compare_field("category_scoring_enabled", per_heat_data['category_scoring_enabled'], hydrated_heat['category_scoring_enabled'])
compare_field("category_score_assignments", per_heat_data['category_score_assignments'], hydrated_heat['category_score_assignments'])

puts ""
puts "First subject comparison:"
if per_heat_data['subjects'].any? && hydrated_heat['subjects'].any?
  per_sub = per_heat_data['subjects'][0]
  hyd_sub = hydrated_heat['subjects'][0]

  compare_field("  id", per_sub['id'], hyd_sub['id'])
  compare_field("  subject.id", per_sub['subject']&.[]('id'), hyd_sub['subject']&.[]('id'))
  compare_field("  subject.name", per_sub['subject']&.[]('name'), hyd_sub['subject']&.[]('name'))
  compare_field("  student_role", per_sub['student_role'], hyd_sub['student_role'])
  compare_field("  scores.length", per_sub['scores']&.length || 0, hyd_sub['scores']&.length || 0)

  if per_sub['scores']&.any?
    puts "  Per-heat first score: #{per_sub['scores'][0].inspect}"
  end
  if hyd_sub['scores']&.any?
    puts "  Hydrated first score: #{hyd_sub['scores'][0].inspect}"
  end
end

puts ""
puts "To see full diff, run:"
puts "  diff #{per_heat_path} #{hydrated_path}"
puts "Or with colors:"
puts "  diff -u #{per_heat_path} #{hydrated_path} | colordiff"
