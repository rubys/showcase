#!/usr/bin/env ruby

require 'csv'
require 'ostruct'

# Parse CSV file and update database
csv_file = "Meals by Studio-Table 1.csv"

unless File.exist?(csv_file)
  puts "Error: CSV file '#{csv_file}' not found"
  exit 1
end

puts "Parsing CSV file: #{csv_file}"

# Track studios, meals, and people from CSV
csv_studios = Set.new
csv_meals = Set.new
csv_people = Hash.new { |h, k| h[k] = Set.new }  # studio => set of people
csv_meal_people = Hash.new { |h, k| h[k] = Hash.new { |hh, kk| hh[kk] = Set.new } }  # meal => studio => people

current_meal = nil

CSV.foreach(csv_file, headers: true) do |row|
  studio_name = row["Studio Name"]&.strip
  meal_name = row["Meal Name"]&.strip
  person_name = row["Attendee Name"]&.strip
  
  next if studio_name.blank? || person_name.blank?
  
  # Skip "Event Staff" studio (studio 0)
  next if studio_name == "Event Staff"
  
  # Use previous meal if current meal is blank
  if meal_name.present?
    current_meal = meal_name
  end
  
  next if current_meal.blank?
  
  # Don't add "Judges & Officials" to csv_studios (they belong to Event Staff)
  csv_studios << studio_name unless studio_name == "Judges & Officials"
  csv_meals << current_meal
  csv_people[studio_name] << person_name
  csv_meal_people[current_meal][studio_name] << person_name
end

puts "Found #{csv_studios.size} studios, #{csv_meals.size} meals, #{csv_people.values.sum(&:size)} people"

# Update Studios (skip studio 0 "Event Staff")
puts "\nUpdating Studios..."
existing_studios = Studio.where.not(id: 0).pluck(:name)
studios_to_add = csv_studios - existing_studios
studios_to_remove = existing_studios - csv_studios.to_a

studios_to_add.each do |studio_name|
  studio = Studio.create!(name: studio_name)
  puts "  Added studio: #{studio_name}"
end

studios_to_remove.each do |studio_name|
  studio = Studio.find_by(name: studio_name)
  if studio
    studio.destroy!
    puts "  Removed studio: #{studio_name}"
  end
end

# Update Guest Options (meals)
puts "\nUpdating Guest Options..."
existing_options = Billable.where(type: 'Option').pluck(:name)
options_to_add = csv_meals - existing_options
options_to_remove = existing_options - csv_meals.to_a

options_to_add.each do |meal_name|
  option = Billable.create!(
    name: meal_name,
    type: 'Option',
    price: 0.0,
    order: Billable.where(type: 'Option').maximum(:order).to_i + 1
  )
  puts "  Added guest option: #{meal_name}"
end

options_to_remove.each do |meal_name|
  option = Billable.find_by(name: meal_name, type: 'Option')
  if option
    option.destroy!
    puts "  Removed guest option: #{meal_name}"
  end
end

# Update People
puts "\nUpdating People..."
csv_people.each do |studio_name, people_names|
  # Intercept "Judges & Officials" and redirect to Event Staff (studio id=0)
  if studio_name == "Judges & Officials"
    studio = Studio.find_by(id: 0) # Event Staff studio
    if studio.nil?
      puts "  Warning: Event Staff studio (id=0) not found, skipping Judges & Officials"
      next
    end
    puts "  Redirecting 'Judges & Officials' people to 'Event Staff' studio"
  else
    studio = Studio.find_by(name: studio_name)
    next unless studio
  end
  
  existing_people = studio.people.where(type: 'Guest').pluck(:name)
  people_to_add = people_names - existing_people
  people_to_remove = existing_people - people_names.to_a
  
  people_to_add.each do |person_name|
    person = Person.find_or_create_by(name: person_name, type: 'Guest') do |p|
      p.role = 'guest'
      p.studio = studio
    end
    if person.studio != studio
      person.studio = studio
      person.save!
    end
    display_studio_name = studio_name == "Judges & Officials" ? "Event Staff" : studio_name
    puts "  Added person: #{person_name} (#{display_studio_name})"
  end
  
  people_to_remove.each do |person_name|
    person = studio.people.find_by(name: person_name, type: 'Guest')
    if person
      person.destroy!
      display_studio_name = studio_name == "Judges & Officials" ? "Event Staff" : studio_name
      puts "  Removed person: #{person_name} (#{display_studio_name})"
    end
  end
end

# Update PersonOption associations
puts "\nUpdating PersonOption associations..."
csv_meal_people.each do |meal_name, studio_people|
  option = Billable.find_by(name: meal_name, type: 'Option')
  next unless option
  
  studio_people.each do |studio_name, people_names|
    # Intercept "Judges & Officials" and redirect to Event Staff (studio id=0)
    if studio_name == "Judges & Officials"
      studio = Studio.find_by(id: 0) # Event Staff studio
      next unless studio
    else
      studio = Studio.find_by(name: studio_name)
      next unless studio
    end
    
    people_names.each do |person_name|
      person = studio.people.find_by(name: person_name, type: 'Guest')
      next unless person
      
      # Create PersonOption if it doesn't exist
      unless PersonOption.exists?(person: person, option: option)
        PersonOption.create!(person: person, option: option)
        puts "  Associated #{person_name} with #{meal_name}"
      end
    end
  end
end

# Clean up orphaned PersonOptions
puts "\nCleaning up orphaned PersonOption associations..."
PersonOption.includes(:person, :option).find_each do |person_option|
  person = person_option.person
  option = person_option.option
  
  next unless person&.type == 'Guest' && option&.type == 'Option'
  
  # Check if this association should exist based on CSV data
  studio_name = person.studio.name
  meal_name = option.name
  person_name = person.name
  
  # For Event Staff studio (id=0), check against "Judges & Officials" in CSV data
  csv_studio_name = (person.studio.id == 0) ? "Judges & Officials" : studio_name
  
  if csv_meal_people[meal_name] && 
     csv_meal_people[meal_name][csv_studio_name] && 
     csv_meal_people[meal_name][csv_studio_name].include?(person_name)
    # Association should exist, keep it
    next
  else
    # Association should not exist, remove it
    person_option.destroy!
    puts "  Removed association: #{person_name} with #{meal_name}"
  end
end

# Run table assignment for each option
puts "\nAssigning people to tables for each option..."
csv_meals.each do |meal_name|
  option = Billable.find_by(name: meal_name, type: 'Option')
  next unless option
  
  puts "  Assigning tables for #{meal_name}..."
  
  begin
    # Create a controller instance and call the assign action
    controller = TablesController.new
    controller.instance_variable_set(:@option, option)
    
    # Mock request object for proper controller initialization
    class MockRequest
      def params
        {}
      end
    end
    controller.instance_variable_set(:@request, MockRequest.new)
    
    # Mock Rails controller methods to avoid context issues
    def controller.redirect_to(*args)
      # Do nothing - just return success
    end
    
    def controller.tables_path(*args)
      # Mock URL helper - just return a dummy path
      "/tables"
    end
    
    # Call the assign method directly
    controller.assign
    
    puts "  ✓ Tables assigned for #{meal_name}"
  rescue => e
    puts "  ✗ Error assigning tables for #{meal_name}: #{e.message}"
    puts "    #{e.backtrace.first}"
  end
end

puts "\nUpdate complete!"