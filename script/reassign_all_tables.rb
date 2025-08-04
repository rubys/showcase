#!/usr/bin/env ruby
# Script to reassign tables for all billable options
# 
# This script:
# 1. Finds all billable options (meal options) in the database
# 2. Clears existing table assignments for each option
# 3. Reassigns tables using the improved algorithm that handles:
#    - Triangular studio pairings (e.g., Escondido-Temecula-Montclair)
#    - Regular studio pairs (e.g., Cary & Merrillville)
#    - Consecutive table numbering for multi-table studios
#    - Proper grid positioning for adjacent seating
# 4. Runs analysis to verify all assignments are correct
# 5. Reports any remaining issues with detailed breakdown
#
# Usage: bin/run [database] script/reassign_all_tables.rb [--pack]
# Examples:
#   bin/run db/2025-torino-april.sqlite3 script/reassign_all_tables.rb
#   bin/run db/2025-torino-april.sqlite3 script/reassign_all_tables.rb --pack
#   bin/run test script/reassign_all_tables.rb
#   bin/run demo script/reassign_all_tables.rb --pack

puts "TABLE REASSIGNMENT SCRIPT"
puts "=" * 50

# Check for pack option
pack_tables = ARGV.include?('--pack')
puts "Pack tables: #{pack_tables ? 'ENABLED' : 'DISABLED'}"
puts

# Get all billable options (meal options)
options = Billable.where(type: 'Option').ordered
puts "Found #{options.count} billable options"

options.each do |option|
  puts "\n" + "-" * 40
  puts "OPTION: #{option.name}"
  puts "-" * 40
  
  # Check current table state
  current_tables = Table.where(option_id: option.id).count
  person_options_with_tables = PersonOption.where(option_id: option.id).joins(:table).count
  total_person_options = PersonOption.where(option_id: option.id).count
  
  puts "Current state:"
  puts "  Tables: #{current_tables}"
  puts "  People assigned to tables: #{person_options_with_tables}"
  puts "  Total PersonOptions: #{total_person_options}"
  
  # Determine if we need to reassign
  needs_reassignment = current_tables > 0 || total_person_options > 0
  
  if needs_reassignment
    puts "  → Reassigning tables..."
    
    # Clear existing table assignments
    if current_tables > 0
      PersonOption.where(option_id: option.id).update_all(table_id: nil)
      Table.where(option_id: option.id).delete_all
      puts "  → Cleared #{current_tables} existing tables"
    end
    
    # Ensure all eligible people have PersonOptions
    eligible_people = Person.where(type: ['Student', 'Professional', 'Guest'])
                           .where.not(studio_id: 0)
                           .includes(:studio)
    
    created_count = 0
    eligible_people.each do |person|
      person_option = PersonOption.find_or_create_by(person: person, option: option)
      created_count += 1 if person_option.previously_new_record?
    end
    
    puts "  → Created #{created_count} new PersonOptions" if created_count > 0
    
    # Run table assignment using the concern methods directly
    begin
      # Create a simple class that includes the TableAssigner concern
      class SimpleAssigner
        include TableAssigner
        attr_accessor :option
        
        def initialize(option)
          @option = option
        end
        
        def assign_with_pack(pack)
          Table.transaction do
            # Clear existing assignments
            PersonOption.where(option_id: @option.id).update_all(table_id: nil)
            Table.where(option_id: @option.id).destroy_all
            
            # Get table size
            table_size = @option.computed_table_size || Event.current&.table_size || 10
            
            # Get people for this option
            people = Person.joins(:studio, :options)
                          .where(person_options: { option_id: @option.id })
                          .order('studios.name, people.name')
            
            if pack
              # Pack mode: create tables sequentially with serpentine grid
              people_groups = group_people_into_packed_tables(people, table_size)
              
              # Create tables with sequential numbering and serpentine grid positions
              created_tables = []
              max_cols = 8  # Standard grid width
              
              people_groups.each_with_index do |group, index|
                # Calculate serpentine grid position
                row = index / max_cols
                col = if row.even?
                  index % max_cols  # Left to right on even rows
                else
                  max_cols - 1 - (index % max_cols)  # Right to left on odd rows
                end
                
                table = Table.create!(
                  number: index + 1,
                  row: row,
                  col: col,
                  option_id: @option.id
                )
                
                # Assign people to this table
                group[:people].each do |person|
                  person_option = PersonOption.find_by(person_id: person.id, option_id: @option.id)
                  person_option&.update!(table_id: table.id)
                end
                
                created_tables << table
              end
              created_tables.count
            else
              # Regular mode: use two-phase algorithm
              people_groups = group_people_into_tables(people, table_size)
              created_tables = place_groups_on_grid(people_groups)
              renumber_tables_by_position
              created_tables.count
            end
          end
        end
      end
      
      assigner = SimpleAssigner.new(option)
      tables_created = assigner.assign_with_pack(pack_tables)
      
      # Verify results
      final_tables = Table.where(option_id: option.id).count
      assigned_people = PersonOption.where(option_id: option.id).joins(:table).count
      
      puts "  → Created #{tables_created} tables"
      puts "  → Assigned #{assigned_people} people to tables"
      
      if final_tables > 0 && assigned_people > 0
        puts "  ✓ SUCCESS"
      else
        puts "  ✗ FAILED"
      end
      
    rescue => e
      puts "  ✗ ERROR: #{e.message}"
      puts "    #{e.backtrace.first}"
    end
  else
    puts "  → No tables or PersonOptions found, skipping"
  end
end

puts "\n" + "=" * 50
puts "REASSIGNMENT COMPLETE"
puts "=" * 50

# Final summary
options.each do |option|
  tables = Table.where(option_id: option.id).count
  people = PersonOption.where(option_id: option.id).joins(:table).count
  puts "#{option.name}: #{tables} tables, #{people} people assigned"
end

puts "\n" + "=" * 50
puts "ANALYZING TABLE ASSIGNMENTS"
puts "=" * 50

# Run the analyze_table_contiguousness method to check for issues
begin
  controller = TablesController.new
  issues = controller.send(:analyze_table_contiguousness)
  
  puts "Total issues found: #{issues.count}"
  
  if issues.empty?
    puts "🎉 PERFECT! NO ISSUES FOUND!"
    puts "✅ All studios with multiple tables have contiguous numbering"
    puts "✅ All studio pairs are seated adjacent to each other"
    puts "✅ All triangular pairings are working correctly"
  else
    puts "\nISSUES FOUND:"
    puts "-" * 40
    
    # Group issues by type for better reporting
    issues_by_type = issues.group_by { |issue| issue[:type] }
    
    issues_by_type.each do |type, type_issues|
      puts "\n#{type.to_s.upcase.gsub('_', ' ')} ISSUES (#{type_issues.count}):"
      
      type_issues.each do |issue|
        if issue[:type] == :non_contiguous_studio
          puts "  • #{issue[:option]}: #{issue[:studio]} has non-contiguous tables: #{issue[:tables].join(', ')}"
        elsif issue[:type] == :non_adjacent_pair
          puts "  • #{issue[:option]}: #{issue[:studio1]} & #{issue[:studio2]} are not adjacent (distance: #{issue[:distance]})"
        end
      end
    end
    
    puts "\n" + "-" * 40
    puts "ISSUE SUMMARY:"
    issues_by_type.each do |type, type_issues|
      puts "  #{type.to_s.gsub('_', ' ').capitalize}: #{type_issues.count} issues"
    end
    
    puts "\nTo fix these issues, re-run the script or check the table assignment algorithm."
  end
  
rescue => e
  puts "✗ ERROR analyzing table assignments: #{e.message}"
  puts "  #{e.backtrace.first}"
end

puts "\n" + "=" * 50
puts "ANALYSIS COMPLETE"
puts "=" * 50