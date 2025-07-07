require "test_helper"

class TableTest < ActiveSupport::TestCase
  test "should require number" do
    table = Table.new(row: 1, col: 1)
    assert_not table.valid?
    assert_includes table.errors[:number], "can't be blank"
  end
  
  test "should be valid with required attributes" do
    table = Table.new(number: 99, row: 3, col: 3, size: 8)
    assert table.valid?
  end
  
  test "should have many people" do
    table = tables(:one)
    person = people(:Arthur)
    person.update!(table: table)
    
    assert_includes table.people, person
  end
  
  test "should enforce unique row and col combination" do
    table1 = tables(:one)
    
    # Try to create another table with same row and col
    table2 = Table.new(number: 99, row: table1.row, col: table1.col)
    assert_not table2.valid?
    assert_includes table2.errors[:row], "and column combination already taken"
  end
  
  test "should enforce unique number" do
    table1 = tables(:one)
    
    # Try to create another table with same number
    table2 = Table.new(number: table1.number, row: 2, col: 2)
    assert_not table2.valid?
    assert_includes table2.errors[:number], "has already been taken"
  end
  
  test "name should show empty when no people assigned" do
    table = Table.new(number: 99)
    assert_equal "Empty", table.name
  end
  
  test "name should show studio names when people assigned" do
    table = tables(:one)
    person1 = people(:Arthur)
    person2 = people(:instructor1)
    
    person1.update!(table: table)
    person2.update!(table: table)
    
    # Both people are from studio "one" based on fixtures
    assert_equal "One", table.name
  end
  
  test "should allow size field to be nil" do
    table = Table.new(number: 99, row: 3, col: 3, size: nil)
    assert table.valid?
  end
  
  test "should allow size field to be a positive integer" do
    table = Table.new(number: 99, row: 3, col: 3, size: 8)
    assert table.valid?
  end
  
  test "should belong to option" do
    table = tables(:one)
    option = billables(:two)  # This is an Option type
    table.update!(option: option)
    
    assert_equal option, table.option
  end
  
  test "should have many person_options" do
    table = tables(:one)
    option = billables(:two)  # This is an Option type
    table.update!(option: option)
    
    person_option = person_options(:one)
    person_option.update!(table: table)
    
    assert_includes table.person_options, person_option
  end
  
  test "should enforce unique number within option scope" do
    option = billables(:two)  # This is an Option type
    table1 = tables(:one)
    table1.update!(option: option)
    
    # Should be able to create table with same number for different option
    # Create another option for testing (e.g., dinner tables vs. main event tables)
    dinner_option = Billable.create!(type: 'Option', name: 'Dinner', price: 25.0)
    table2 = Table.new(number: table1.number, row: 2, col: 2, option: dinner_option)
    assert table2.valid?
    
    # Should not be able to create table with same number for same option
    table3 = Table.new(number: table1.number, row: 3, col: 3, option: option)
    assert_not table3.valid?
    assert_includes table3.errors[:number], "has already been taken"
  end
  
  test "should enforce unique row and col within option scope" do
    option = billables(:two)  # This is an Option type
    table1 = tables(:one)
    table1.update!(option: option)
    
    # Should be able to create table with same position for different option
    # Create another option for testing (e.g., dinner tables vs. main event tables)
    dinner_option = Billable.create!(type: 'Option', name: 'Dinner', price: 25.0)
    table2 = Table.new(number: 99, row: table1.row, col: table1.col, option: dinner_option)
    assert table2.valid?
    
    # Should not be able to create table with same position for same option
    table3 = Table.new(number: 100, row: table1.row, col: table1.col, option: option)
    assert_not table3.valid?
    assert_includes table3.errors[:row], "and column combination already taken"
  end
  
  test "name should show studios from person_options for option tables" do
    table = tables(:one)
    option = billables(:two)  # This is an Option type
    table.update!(option: option)
    
    # Create person_options for this table
    person1 = people(:Arthur)
    person2 = people(:instructor1)
    
    PersonOption.create!(person: person1, option: option, table: table)
    PersonOption.create!(person: person2, option: option, table: table)
    
    # Both people are from studio "one" based on fixtures
    assert_equal "One", table.name
  end
  
  test "name should return empty for option table with no person_options" do
    table = tables(:one)
    option = billables(:two)  # This is an Option type
    table.update!(option: option)
    
    assert_equal "Empty", table.name
  end
end
