#!/usr/bin/env ruby

require 'sqlite3'

# Get the db directory path
db_dir = File.join(File.dirname(__FILE__), '..', 'db')

# Find all SQLite database files
db_files = Dir.glob(File.join(db_dir, '*.sqlite3'))

puts "Scanning #{db_files.length} database files...\n\n"

# Track databases with semi_finals
databases_with_semi_finals = []

db_files.each do |db_file|
  begin
    # Open the database
    db = SQLite3::Database.new(db_file)
    
    # Check if dances table exists
    table_check = "SELECT name FROM sqlite_master WHERE type='table' AND name='dances';"
    tables = db.execute(table_check)
    
    if tables.any?
      # Check for semi_finals column
      column_check = "PRAGMA table_info(dances);"
      columns = db.execute(column_check)
      has_semi_finals = columns.any? { |col| col[1] == 'semi_finals' }
      
      if has_semi_finals
        # Query for non-zero semi_finals values
        query = "SELECT COUNT(*) FROM dances WHERE semi_finals != 0 AND semi_finals IS NOT NULL;"
        result = db.execute(query).first.first
        
        if result > 0
          # Get some details about the dances with semi_finals
          details_query = "SELECT name, semi_finals FROM dances WHERE semi_finals != 0 AND semi_finals IS NOT NULL ORDER BY semi_finals DESC LIMIT 5;"
          details = db.execute(details_query)
          
          databases_with_semi_finals << {
            file: File.basename(db_file),
            count: result,
            details: details
          }
        end
      end
    end
    
    db.close
  rescue SQLite3::Exception => e
    puts "Error processing #{File.basename(db_file)}: #{e.message}"
  end
end

# Display results
if databases_with_semi_finals.empty?
  puts "No databases found with non-zero semi_finals values in the dances table."
else
  puts "Found #{databases_with_semi_finals.length} database(s) with non-zero semi_finals values:\n\n"
  
  databases_with_semi_finals.each do |db_info|
    puts "Database: #{db_info[:file]}"
    puts "  Total dances with semi_finals: #{db_info[:count]}"
    puts "  Examples:"
    db_info[:details].each do |dance, semi_finals|
      puts "    - #{dance}: #{semi_finals}"
    end
    puts
  end
end