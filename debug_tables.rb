#!/usr/bin/env ruby

# Debug single option table assignment

puts "DEBUG TABLE ASSIGNMENT"
puts "=" * 50

# Get first option
option = Billable.where(type: 'Option').first
puts "OPTION: #{option.name}"

# Clear existing tables
PersonOption.where(option_id: option.id).update_all(table_id: nil)
Table.where(option_id: option.id).delete_all

# Create controller and run assignment
class DebugController < TablesController
  def initialize(option)
    super()
    @option = option
  end
  
  def debug_assign
    Table.transaction do
      # Get table size
      table_size = 10
      
      # Get people
      people = Person.joins(:studio, :options)
                     .where(person_options: { option_id: @option.id })
                     .order('studios.name, people.name')
      
      puts "People: #{people.count}"
      
      # Run assignment
      people_groups = group_people_into_tables(people, table_size)
      puts "People groups: #{people_groups.count}"
      
      # Check studio_ids
      people_groups.each_with_index do |group, i|
        studio_ids = group[:studio_ids] || [group[:studio_id]]
        puts "Group #{i}: #{group[:studio_name]}, studio_ids: #{studio_ids}, people: #{group[:people].size}"
      end
      
      # Specifically check NY-Broadway groups
      puts "\nNY-Broadway groups BEFORE placement:"
      people_groups.each_with_index do |group, i|
        if group[:studio_name] && group[:studio_name].include?("NY-Broadway")
          studio_ids = group[:studio_ids] || [group[:studio_id]]
          ny_broadway_id = Studio.find_by(name: "NY-Broadway")&.id
          has_ny_broadway = studio_ids.include?(ny_broadway_id)
          puts "  Group #{i}: #{group[:studio_name]}, coordination_group: #{group[:coordination_group]}, split_group: #{group[:split_group]}"
        end
      end
      
      # Check which studios appear in multiple groups
      studio_to_groups = Hash.new { |h, k| h[k] = [] }
      people_groups.each_with_index do |group, index|
        studio_ids = group[:studio_ids] || [group[:studio_id]]
        studio_ids.each do |studio_id|
          studio_to_groups[studio_id] << { group: group, index: index }
        end
      end
      
      puts "\nStudios appearing in multiple groups:"
      studio_to_groups.each do |studio_id, group_refs|
        if studio_id && studio_id != 0 && group_refs.length > 1
          studio_name = group_refs.first[:group][:people].first.studio.name
          puts "  Studio #{studio_id} (#{studio_name}): #{group_refs.length} groups"
        end
      end
      
      # Enable verbose logging
      Rails.logger.level = Logger::INFO
      
      place_groups_on_grid(people_groups)
      
      # Check final table assignments
      puts "\nFinal table assignments:"
      tables = Table.where(option_id: @option.id).includes(:person_options => {:person => :studio}).order(:number)
      tables.each do |table|
        studios = table.person_options.map { |po| po.person.studio.name }.uniq
        puts "  Table #{table.number}: #{studios.join(', ')}"
      end
      
      # Check specific studios
      puts "\nStudio table assignments:"
      studios_to_check = ['Silver Spring', 'Lincolnshire', 'Waco', 'Greenwich', 'San Jose']
      studios_to_check.each do |studio_name|
        tables_for_studio = Table.joins(:person_options => {:person => :studio})
                                 .where(option_id: @option.id)
                                 .where(studios: {name: studio_name})
                                 .distinct
                                 .order(:number)
        table_numbers = tables_for_studio.pluck(:number)
        puts "  #{studio_name}: #{table_numbers.join(', ')}"
      end
    end
  end
end

controller = DebugController.new(option)
controller.debug_assign