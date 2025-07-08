#!/usr/bin/env ruby

require 'csv'
require 'sqlite3'

# Database path
db_path = 'db/2025-monza-praga.sqlite3'
csv_path = 'tmp/MealCounts.csv'

# Connect to database
db = SQLite3::Database.new(db_path)

puts "Updating studios and people based on meal counts..."

# Read CSV file
csv_data = CSV.read(csv_path, headers: true)

# Collect studio names and counts from CSV
csv_studios = {}
csv_data.each do |row|
  studio_name = row['Studio Name']
  
  # Skip empty rows and "Judges & Officials"
  next if studio_name.nil? || studio_name.strip.empty? || studio_name == "Judges & Officials"
  
  # Find maximum count across all meal columns
  meal_columns = row.headers - ['Studio Name']
  max_count = 0
  
  meal_columns.each do |col|
    value = row[col].to_i
    max_count = value if value > max_count
  end
  
  csv_studios[studio_name] = max_count
end

# Get existing studios (excluding Event Staff with id=0)
existing_studios = {}
db.execute("SELECT id, name FROM studios WHERE id != 0") do |row|
  existing_studios[row[1]] = row[0]  # name => id
end

# Remove studios that are no longer in the CSV
studios_to_remove = existing_studios.keys - csv_studios.keys
studios_to_remove.each do |studio_name|
  studio_id = existing_studios[studio_name]
  puts "Removing studio: #{studio_name}"
  
  # Delete people first (foreign key constraint)
  db.execute("DELETE FROM people WHERE studio_id = ?", [studio_id])
  # Delete studio
  db.execute("DELETE FROM studios WHERE id = ?", [studio_id])
end

# Process each studio from CSV
csv_studios.each do |studio_name, target_count|
  puts "Processing #{studio_name}: #{target_count} guests"
  
  if existing_studios.key?(studio_name)
    # Studio exists - update people count
    studio_id = existing_studios[studio_name]
    
    # Get current count of guests for this studio
    current_count = db.execute("SELECT COUNT(*) FROM people WHERE studio_id = ? AND type = 'Guest'", [studio_id])[0][0]
    
    if current_count < target_count
      # Add more people
      people_to_add = target_count - current_count
      puts "  Adding #{people_to_add} guests to #{studio_name}"
      
      (current_count + 1..target_count).each do |i|
        guest_name = "#{studio_name} #{i}"
        db.execute(
          "INSERT INTO people (name, type, studio_id, created_at, updated_at) VALUES (?, 'Guest', ?, datetime('now'), datetime('now'))",
          [guest_name, studio_id]
        )
      end
    elsif current_count > target_count
      # Remove excess people
      people_to_remove = current_count - target_count
      puts "  Removing #{people_to_remove} guests from #{studio_name}"
      
      # Get IDs of guests to remove (remove the highest numbered ones)
      guest_ids = db.execute(
        "SELECT id FROM people WHERE studio_id = ? AND type = 'Guest' ORDER BY name DESC LIMIT ?", 
        [studio_id, people_to_remove]
      ).map { |row| row[0] }
      
      guest_ids.each do |guest_id|
        db.execute("DELETE FROM people WHERE id = ?", [guest_id])
      end
    else
      puts "  #{studio_name} already has correct count (#{current_count})"
    end
    
    # Update studio timestamp
    db.execute("UPDATE studios SET updated_at = datetime('now') WHERE id = ?", [studio_id])
  else
    # New studio - create it
    puts "  Creating new studio: #{studio_name}"
    db.execute("INSERT INTO studios (name, created_at, updated_at) VALUES (?, datetime('now'), datetime('now'))", [studio_name])
    studio_id = db.last_insert_row_id
    
    # Create guests for this studio
    (1..target_count).each do |i|
      guest_name = "#{studio_name} #{i}"
      db.execute(
        "INSERT INTO people (name, type, studio_id, created_at, updated_at) VALUES (?, 'Guest', ?, datetime('now'), datetime('now'))",
        [guest_name, studio_id]
      )
    end
  end
end

puts "Done! Studios and people updated based on meal counts."