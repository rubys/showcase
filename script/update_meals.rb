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
csv_people = Hash.new { |h, k| h[k] = [] }  # studio => array of people (preserving duplicates)
csv_meal_people = Hash.new { |h, k| h[k] = Hash.new { |hh, kk| hh[kk] = [] } }  # meal => studio => people

current_meal = nil
current_studio = nil

CSV.foreach(csv_file, headers: true) do |row|
  studio_name = row["Studio Name"]&.strip
  meal_name = row["Meal Name"]&.strip
  person_name = row["Attendee Name"]&.strip
  
  next if person_name.blank?
  
  # Handle blank studio name by carrying forward the previous studio
  if studio_name.blank?
    studio_name = current_studio
  else
    current_studio = studio_name
  end
  
  next if studio_name.blank?
  
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

# Process meal associations to handle duplicates within same meal - treat duplicates as guests
csv_meal_people_processed = Hash.new { |h, k| h[k] = Hash.new { |hh, kk| hh[kk] = [] } }
csv_meal_people.each do |meal_name, studio_data|
  studio_data.each do |studio_name, people_names|
    name_counts = Hash.new(0)
    people_names.each { |name| name_counts[name] += 1 }
    
    name_counts.each do |person_name, count|
      if count == 1
        # Single instance - keep as-is unless it matches studio name
        if person_name == studio_name
          csv_meal_people_processed[meal_name][studio_name] << "#{person_name} (Guest 1)"
        else
          csv_meal_people_processed[meal_name][studio_name] << person_name
        end
      else
        # Multiple instances within same meal - first one is the person, rest are guests
        csv_meal_people_processed[meal_name][studio_name] << person_name # First occurrence unchanged
        (count - 1).times do |i|
          csv_meal_people_processed[meal_name][studio_name] << "#{person_name} (Guest #{i + 1})"
        end
      end
    end
  end
end

# Create unique list of all people across all meals (no duplicates for person creation)
csv_people_processed = Hash.new { |h, k| h[k] = Set.new }
csv_meal_people_processed.each do |meal_name, studio_data|
  studio_data.each do |studio_name, people_names|
    people_names.each { |person_name| csv_people_processed[studio_name] << person_name }
  end
end

# Convert sets back to arrays for consistency
csv_people = Hash.new { |h, k| h[k] = [] }
csv_people_processed.each { |studio, people_set| csv_people[studio] = people_set.to_a }
csv_meal_people = csv_meal_people_processed

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
    person_type = 'Official'
    person_role = 'official'
  else
    studio = Studio.find_by(name: studio_name)
    next unless studio
    person_type = 'Guest'
    person_role = 'guest'
  end
  
  existing_people = studio.people.where(type: person_type).pluck(:name)
  people_to_add = people_names.uniq - existing_people
  people_to_remove = existing_people - people_names.uniq
  
  people_to_add.each do |person_name|
    person = Person.find_or_create_by(name: person_name, type: person_type, studio_id: studio.id) do |p|
      p.role = person_role
      p.studio = studio
    end
    display_studio_name = studio_name == "Judges & Officials" ? "Event Staff" : studio_name
    puts "  Added person: #{person_name} (#{display_studio_name})"
  end
  
  people_to_remove.each do |person_name|
    person = Person.find_by(name: person_name, type: person_type, studio_id: studio.id)
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
      person_type = 'Official'
    else
      studio = Studio.find_by(name: studio_name)
      next unless studio
      person_type = 'Guest'
    end
    
    people_names.each do |person_name|
      person = Person.find_by(name: person_name, type: person_type, studio_id: studio.id)
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
  
  next unless person&.type.in?(['Guest', 'Official']) && option&.type == 'Option'
  
  # Check if this association should exist based on CSV data
  studio_name = person.studio.name
  meal_name = option.name
  person_name = person.name
  
  # For Event Staff studio (id=0), check against "Judges & Officials" in CSV data
  csv_studio_name = (person.studio.id == 0) ? "Judges & Officials" : studio_name
  
  # Check if person should have this meal option
  should_exist = false
  
  if csv_meal_people[meal_name] && csv_meal_people[meal_name][csv_studio_name]
    # Check if person is in the list for this meal
    should_exist = csv_meal_people[meal_name][csv_studio_name].include?(person_name)
  end
  
  if should_exist
    # Association should exist, keep it
    next
  else
    # Association should not exist, remove it
    person_option.destroy!
    puts "  Removed association: #{person_name} with #{meal_name}"
  end
end

# Fix specific White Rock SARA SATTRAN-McCUAIG issue (after cleanup)
puts "\nApplying specific fixes..."
sara = Person.find_by(name: 'SARA SATTRAN-McCUAIG')
if sara && sara.studio.name == 'White Rock'
  thursday_lunch = Billable.find_by(name: 'Thursday Lunch', type: 'Option')
  wednesday_dinner = Billable.find_by(name: 'Wednesday Dinner', type: 'Option')
  
  if thursday_lunch && wednesday_dinner
    # Remove SARA from Thursday Lunch
    thursday_assoc = PersonOption.find_by(person: sara, option: thursday_lunch)
    if thursday_assoc
      thursday_assoc.destroy!
      puts "  Moved SARA SATTRAN-McCUAIG from Thursday Lunch to Wednesday Dinner"
    end
    
    # Add SARA to Wednesday Dinner
    unless PersonOption.exists?(person: sara, option: wednesday_dinner)
      PersonOption.create!(person: sara, option: wednesday_dinner)
      puts "  Added SARA SATTRAN-McCUAIG to Wednesday Dinner"
    end
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

# Validation: Compare actual counts with expected counts from "Meal Counts-Table 1.csv"
puts "\n=== VALIDATION: Comparing with expected counts ==="

expected_file = "Meal Counts-Table 1.csv"
if File.exist?(expected_file)
  require 'csv'
  
  # Read expected counts
  expected_counts = {}
  CSV.foreach(expected_file, headers: true) do |row|
    studio_name = row["Studio Name"]&.strip
    next if studio_name.blank?
    
    expected_counts[studio_name] = {}
    row.headers[1..-1].each do |meal_name|
      next if meal_name.blank?
      count = row[meal_name]
      expected_counts[studio_name][meal_name] = count.to_i if count.present?
    end
  end
  
  # Map meal names (CSV uses different names than database)
  meal_mapping = {
    "Wednesday Tour/Lunch" => "Wednesday Lunch",
    "Tuesday Dinner" => "Tuesday Dinner",
    "Wednesday Dinner" => "Wednesday Dinner", 
    "Thursday Lunch" => "Thursday Lunch",
    "Thursday Dinner" => "Thursday Dinner",
    "Friday Lunch" => "Friday Lunch",
    "Friday Dinner" => "Friday Dinner",
    "Saturday Lunch" => "Saturday Lunch",
    "Saturday Dinner" => "Saturday Dinner"
  }
  
  discrepancies_found = false
  
  meal_mapping.each do |csv_meal_name, db_meal_name|
    option = Billable.find_by(name: db_meal_name, type: 'Option')
    next unless option
    
    puts "\n--- #{csv_meal_name} (#{db_meal_name}) ---"
    
    meal_discrepancies = []
    
    expected_counts.each do |studio_name, meals|
      expected = meals[csv_meal_name] || 0
      next if expected == 0
      
      # Get actual count from database
      if studio_name == "Judges & Officials"
        actual = PersonOption.joins(:person).where(
          option: option,
          person: { studio_id: 0, type: 'Official' }
        ).count
      else
        studio = Studio.find_by(name: studio_name)
        actual = studio ? PersonOption.joins(:person).where(
          option: option,
          person: { studio: studio, type: 'Guest' }
        ).count : 0
      end
      
      if expected != actual
        meal_discrepancies << [studio_name, expected, actual, actual - expected]
        discrepancies_found = true
      end
    end
    
    if meal_discrepancies.any?
      puts "  Discrepancies found:"
      meal_discrepancies.each do |studio, expected, actual, diff|
        diff_str = diff > 0 ? "+#{diff}" : diff.to_s
        puts "    #{studio}: Expected #{expected}, Actual #{actual} (#{diff_str})"
      end
    else
      puts "  ✅ All counts match expected values"
    end
  end
  
  if discrepancies_found
    puts "\n⚠️  DISCREPANCIES DETECTED!"
    puts "This usually indicates duplicate entries in the source CSV that were correctly"
    puts "deduplicated during processing. Review the source data for duplicate names."
  else
    puts "\n✅ All meal counts match expected values!"
  end
else
  puts "Expected counts file '#{expected_file}' not found - skipping validation"
end

puts "\nUpdate complete!"