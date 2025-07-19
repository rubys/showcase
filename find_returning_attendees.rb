#!/usr/bin/env ruby

require 'sqlite3'
require 'set'

# Find all event databases
event_dbs = Dir.glob('db/*.sqlite3').select { |f| File.basename(f) =~ /^\d{4}/ }

# Separate current event from previous events
current_event = 'db/2025-torino-april.sqlite3'
previous_events = event_dbs - [current_event]

unless File.exist?(current_event)
  puts "Error: #{current_event} not found"
  exit 1
end

# Get all people from the current event
current_db = SQLite3::Database.new(current_event)
current_people = {}

current_db.execute("SELECT id, name, type FROM people") do |row|
  current_people[row[1]] = { id: row[0], type: row[2] }
end

current_db.close

# Track which previous events each person attended
returning_attendees = {}

# Check each previous event
previous_events.sort.each do |event_file|
  event_name = File.basename(event_file, '.sqlite3')
  
  begin
    db = SQLite3::Database.new(event_file)
    
    # Check if people table exists
    table_exists = db.get_first_value("SELECT name FROM sqlite_master WHERE type='table' AND name='people'")
    
    if table_exists
      # Find people who match by name
      current_people.each do |name, info|
        count = db.get_first_value("SELECT COUNT(*) FROM people WHERE name = ?", name)
        
        if count && count > 0
          returning_attendees[name] ||= { type: info[:type], events: [] }
          returning_attendees[name][:events] << event_name
        end
      end
    end
    
    db.close
  rescue SQLite3::Exception => e
    puts "Warning: Error reading #{event_file}: #{e.message}"
  end
end

# Display results
puts "People at 2025-torino-april who attended previous events:"
puts "=" * 60
puts

if returning_attendees.empty?
  puts "No returning attendees found."
else
  returning_attendees.sort_by { |name, _| name }.each do |name, info|
    puts "#{name} (#{info[:type]})"
    puts "  Previous events: #{info[:events].join(', ')}"
    puts
  end
  
  puts "-" * 60
  puts "Total returning attendees: #{returning_attendees.size}"
  puts "Out of #{current_people.size} total attendees at 2025-torino-april"
  
  # Group by number of events attended
  puts "\nBreakdown by number of previous events:"
  by_event_count = returning_attendees.group_by { |_, info| info[:events].size }
  by_event_count.sort.reverse.each do |count, people|
    puts "  #{count} previous event#{'s' if count > 1}: #{people.size} people"
  end
  
  # Find the most frequent attendees
  puts "\nMost frequent attendees (10+ previous events):"
  returning_attendees.select { |_, info| info[:events].size >= 10 }
    .sort_by { |_, info| -info[:events].size }
    .each do |name, info|
      puts "  #{name} (#{info[:type]}): #{info[:events].size} events"
    end
end