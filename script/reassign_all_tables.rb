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
# Usage: bin/run [database] script/reassign_all_tables.rb
# Examples:
#   bin/run db/2025-torino-april.sqlite3 script/reassign_all_tables.rb
#   bin/run test script/reassign_all_tables.rb
#   bin/run demo script/reassign_all_tables.rb

puts "TABLE REASSIGNMENT SCRIPT"
puts "=" * 50

# Get all billable options (meal options)
options = Billable.where(type: 'Option').order(:order)
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
    
    # Run table assignment using the actual controller method
    begin
      # Create a controller instance and call the actual assign method
      class TestController < TablesController
        def initialize(option)
          super()
          @option = option
        end
        
        def call_assign
          # Call the actual assign method from the controller
          assign_internal
        end
        
        private
        
        def assign_internal
          Table.transaction do
            # Remove all existing tables for this option context
            if @option
              # For option tables, also clear table_id from person_options
              PersonOption.where(option_id: @option.id).update_all(table_id: nil)
              Table.where(option_id: @option.id).destroy_all
            else
              # For main event, clear people's table_id (dependent: :nullify will handle this)
              Table.where(option_id: nil).destroy_all
            end
            
            # Get table size using computed method
            table_size = @option&.computed_table_size || Event.current&.table_size || 10
            
            # Get people based on context
            if @option
              # For option tables, get people who have registered for this option
              people = Person.joins(:studio, :options)
                             .where(person_options: { option_id: @option.id })
                             .order('studios.name, people.name')
            else
              # For main event tables, get all people
              people = Person.joins(:studio).order('studios.name, people.name')
            end
            
            # TWO-PHASE ALGORITHM
            # Phase 1: Group people into tables (who sits together)
            people_groups = group_people_into_tables(people, table_size)
            
            # Phase 2: Place groups on grid (where tables go)
            created_tables = place_groups_on_grid(people_groups)
            
            # Renumber tables sequentially based on their final positions
            renumber_tables_by_position
            
            created_tables.count
          end
        end
      end
      
      controller = TestController.new(option)
      tables_created = controller.call_assign
      
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