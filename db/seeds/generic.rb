require 'yaml'

config = YAML.load(IO.read "#{__dir__}/generic.yaml")

###

Event.delete_all
event = Event.create!(
  name: config[:settings][:event][:name],
  location: config[:settings][:event][:location],
  heat_range_cat: config[:settings][:heat][:category],
  heat_range_level: config[:settings][:heat][:level],
  heat_range_age: config[:settings][:heat][:age],
)

db_basename = ENV[ "RAILS_APP_DB"]
if db_basename.blank? && ENV['DATABASE_URL']
  db_basename = File.basename(ENV['DATABASE_URL'], '.sqlite3')
end

# Check for showcases.yml and update event with date/name if available
if db_basename.present?
  # Parse database URL to extract year, location, and optional event key
  # Expected format: .../YEAR-LOCATION.sqlite3 or .../YEAR-LOCATION-EVENT.sqlite3
  parts = db_basename.split('-')

  if parts.length >= 2
    year = parts[0].to_i
    location_key = parts[1]
    event_key = parts.length > 2 ? parts[2..-1].join('-') : nil

    # Load showcases data
    showcases_data = ShowcasesLoader.load
    
    # Find the location data for this year
    location_data = showcases_data.dig(year, location_key)
    
    if location_data
      # Check if there are multiple events for this location
      if location_data[:events] && event_key
        # Multiple events - find the specific event
        event_data = location_data[:events][event_key]
        if event_data
          event.update!(
            name: event_data[:name],
            date: event_data[:date]
          )
        end
      elsif location_data[:date]
        # Single event - use the date directly from location
        event.update!(date: location_data[:date])
      end
    end
  end
end

Studio.delete_all
Studio.create! name: 'Event Staff', id: 0

Age.delete_all
ages = config[:ages].map do |category, description|
  [category, Age.create!(category: category, description: description)]
end.to_h

Level.delete_all
levels = config[:levels].map do |name|
  [name, Level.create!(name: name)]
end.to_h

Dance.delete_all
order = 0
config[:dances].to_a.map do |dance|
  order += 1
  [dance, Dance.create!(name: dance, order: order)]
end.to_h
