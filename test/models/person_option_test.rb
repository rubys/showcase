require "test_helper"

class PersonOptionTest < ActiveSupport::TestCase
  test "should belong to table" do
    person_option = person_options(:one)
    table = tables(:one)
    # First ensure the table has the same option as the person_option
    table.update!(option: person_option.option)
    person_option.update!(table: table)
    
    assert_equal table, person_option.table
  end
  
  test "table should be optional" do
    person_option = person_options(:one)
    person_option.table = nil
    assert person_option.valid?
  end
  
  test "should validate table belongs to same option" do
    person_option = person_options(:one)
    option1 = person_option.option
    # Create another option for testing (e.g., dinner tables)
    dinner_option = Billable.create!(type: 'Option', name: 'Dinner', price: 25.0)
    
    # Create a table for a different option
    table = tables(:one)
    table.update!(option: dinner_option)
    
    # Try to assign this table to person_option with different option
    person_option.table = table
    assert_not person_option.valid?
    assert_includes person_option.errors[:table], "must belong to the same option"
  end
  
  test "should allow table assignment when table has same option" do
    person_option = person_options(:one)
    option = person_option.option
    
    # Create a table for the same option
    table = tables(:one)
    table.update!(option: option)
    
    person_option.table = table
    assert person_option.valid?
  end
  
  test "should allow nil table even when option is set" do
    person_option = person_options(:one)
    person_option.table = nil
    assert person_option.valid?
  end
end
