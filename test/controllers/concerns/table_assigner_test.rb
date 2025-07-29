require "test_helper"

class TableAssignerTest < ActionDispatch::IntegrationTest
  include TableAssigner
  
  setup do
    @event = events(:one)
    @option = nil  # Main event context
    # Clean up any existing tables to avoid conflicts
    Table.destroy_all
  end

  test "should not assign people already at locked tables" do
    # Create a locked table with some people
    locked_table = Table.create!(number: 1, locked: true, row: 0, col: 0)
    person1 = people(:student_one)
    person2 = people(:student_two)
    person1.update!(table: locked_table)
    
    # Count people before assignment
    unassigned_people_count = Person.where(table_id: nil).count
    
    # Run table assignment
    assign_tables(pack: false)
    
    # Verify person at locked table wasn't moved
    person1.reload
    assert_equal locked_table.id, person1.table_id
    
    # Verify the locked table still exists with same number
    assert Table.exists?(locked_table.id)
    assert_equal 1, locked_table.reload.number
    assert locked_table.locked?
  end

  test "should respect existing locked table positions" do
    # Create locked tables at specific positions
    locked_table1 = Table.create!(number: 5, locked: true, row: 0, col: 4)
    locked_table2 = Table.create!(number: 10, locked: true, row: 1, col: 1)
    
    # Run table assignment
    assign_tables(pack: false)
    
    # Verify no new tables were placed at locked positions
    tables_at_locked_positions = Table.where(row: 0, col: 4).or(Table.where(row: 1, col: 1))
    assert_equal 2, tables_at_locked_positions.count
    assert tables_at_locked_positions.all?(&:locked?)
  end

  test "should avoid locked table numbers when creating new tables" do
    # Create locked tables with specific numbers
    locked_table1 = Table.create!(number: 3, locked: true, row: 0, col: 2)
    locked_table2 = Table.create!(number: 7, locked: true, row: 0, col: 6)
    
    # Run table assignment
    assign_tables(pack: false)
    
    # Verify no new tables have the same numbers as locked tables
    unlocked_tables = Table.where(locked: false)
    unlocked_numbers = unlocked_tables.pluck(:number)
    
    assert_not_includes unlocked_numbers, 3
    assert_not_includes unlocked_numbers, 7
  end

  test "should only renumber unlocked tables" do
    # Create a mix of locked and unlocked tables
    locked_table = Table.create!(number: 2, locked: true, row: 0, col: 1)
    unlocked_table1 = Table.create!(number: 1, locked: false, row: 0, col: 0)
    unlocked_table2 = Table.create!(number: 3, locked: false, row: 0, col: 2)
    
    # Renumber tables
    renumber_tables_by_position
    
    # Verify locked table kept its number
    assert_equal 2, locked_table.reload.number
    
    # Verify unlocked tables were renumbered avoiding the locked number
    unlocked_numbers = [unlocked_table1.reload.number, unlocked_table2.reload.number].sort
    assert_equal [1, 3], unlocked_numbers
  end

  test "should handle option context with locked tables" do
    option = billables(:two)  # Lunch option from fixtures
    @option = option
    
    # Create a locked table for the option
    locked_table = Table.create!(number: 1, locked: true, row: 0, col: 0, option: option)
    
    # Create person with option and assign to locked table
    person = people(:Arthur)
    person_option = PersonOption.create!(person: person, option: option, table: locked_table)
    
    # Add more people with the option
    people(:Kathryn).options.create!(option: option)
    people(:instructor1).options.create!(option: option)
    
    # Count how many people have this option before assignment
    initial_option_count = PersonOption.where(option: option).count
    people_with_option_through_package = Person.joins(package: { package_includes: :option })
                                               .where(package_includes: { option_id: option.id })
                                               .count
    total_with_access = initial_option_count + people_with_option_through_package
    
    # Run table assignment
    assign_tables(pack: false)
    
    # Verify person at locked table wasn't moved
    person_option.reload
    assert_equal locked_table.id, person_option.table_id
    
    # Verify that the people we explicitly added options for were assigned
    # (There might be others with the option through packages)
    assert_not_nil people(:Kathryn).options.find_by(option: option).table_id, "Kathryn should be assigned to a table"
    assert_not_nil people(:instructor1).options.find_by(option: option).table_id, "instructor1 should be assigned to a table"
  end

  test "should work with pack mode and locked tables" do
    # Create a locked table
    locked_table = Table.create!(number: 5, locked: true, row: 0, col: 4)
    person = people(:student_one)
    person.update!(table: locked_table)
    
    # Run table assignment in pack mode
    assign_tables(pack: true)
    
    # Verify locked table and person assignment preserved
    person.reload
    assert_equal locked_table.id, person.table_id
    assert Table.exists?(locked_table.id)
  end

  test "remove_unlocked_tables should preserve locked tables" do
    # Create tables
    locked_table = Table.create!(number: 1, locked: true)
    unlocked_table = Table.create!(number: 2, locked: false)
    
    # Remove unlocked tables
    remove_unlocked_tables(nil)
    
    # Verify only unlocked table was removed
    assert Table.exists?(locked_table.id)
    assert_not Table.exists?(unlocked_table.id)
  end

  test "should handle studio pairs with locked tables" do
    # Create studio pair
    studio1 = studios(:one)
    studio2 = studios(:two)
    StudioPair.create!(studio1: studio1, studio2: studio2)
    
    # Create locked table with someone from studio1
    locked_table = Table.create!(number: 1, locked: true, row: 0, col: 0)
    person_from_studio1 = Person.where(studio: studio1).first
    person_from_studio1.update!(table: locked_table)
    
    # Run table assignment
    assign_tables(pack: false)
    
    # Verify person at locked table wasn't moved
    person_from_studio1.reload
    assert_equal locked_table.id, person_from_studio1.table_id
    
    # Verify other people from both studios were placed appropriately
    unassigned_from_studio1 = Person.where(studio: studio1, table_id: nil)
    unassigned_from_studio2 = Person.where(studio: studio2, table_id: nil)
    assert unassigned_from_studio1.empty?
    assert unassigned_from_studio2.empty?
  end

  test "should handle edge case with all tables locked" do
    # Create all people at locked tables
    people_to_assign = Person.where(type: ['Student', 'Professional', 'Guest']).where.not(studio_id: 0)
    people_to_assign.each_with_index do |person, idx|
      table = Table.create!(number: idx + 1, locked: true, row: idx / 8, col: idx % 8)
      person.update!(table: table)
    end
    
    # Also handle judges (Event Staff with studio_id: 0)
    Person.where(studio_id: 0).each_with_index do |person, idx|
      table = Table.create!(number: 100 + idx, locked: true, row: 10 + idx / 8, col: idx % 8)
      person.update!(table: table)
    end
    
    # Count tables before
    tables_before = Table.count
    
    # Run table assignment - should create no new tables
    assign_tables(pack: false)
    
    # Verify no new tables were created
    assert_equal tables_before, Table.count
  end

  test "should maintain grid integrity with scattered locked tables" do
    # Create locked tables in a checkerboard pattern
    locked_positions = [[0, 0], [0, 2], [0, 4], [1, 1], [1, 3], [2, 0], [2, 2]]
    locked_positions.each_with_index do |(row, col), idx|
      Table.create!(number: idx + 1, locked: true, row: row, col: col)
    end
    
    # Run table assignment
    assign_tables(pack: false)
    
    # Verify no position has multiple tables
    position_counts = Table.group(:row, :col).count
    position_counts.each do |position, count|
      assert_equal 1, count, "Position #{position} has #{count} tables"
    end
  end
end