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
    dinner_option = Billable.create!(type: 'Option', name: "Dinner #{rand(1000)}", price: 25.0)
    
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
  
  test "cleanup_if_only_from_package removes record when option is from package" do
    # Create a package with an option included
    package = Billable.create!(type: 'Package', name: "Test Package #{rand(1000)}", price: 100.0)
    option = Billable.create!(type: 'Option', name: "Test Option #{rand(1000)}", price: 25.0)
    PackageInclude.create!(package: package, option: option)
    
    # Create a person with this package
    studio = studios(:one)
    person = Person.create!(name: "Test#{rand(1000)}, Person", type: 'Student', studio: studio, package: package, level: levels(:FS), age: ages(:A))
    
    # Create a PersonOption record (as if they were seated at a table)
    person_option = PersonOption.create!(person: person, option: option)
    
    # Cleanup should destroy the record since they only have it through package
    assert_difference 'PersonOption.count', -1 do
      result = PersonOption.cleanup_if_only_from_package(person_option)
      assert result # Should return true when destroyed
    end
  end
  
  test "cleanup_if_only_from_package keeps record when option is directly selected" do
    # Create an option without package
    option = Billable.create!(type: 'Option', name: "Test Option #{rand(1000)}", price: 25.0)
    
    # Create a person without package
    studio = studios(:one)
    person = Person.create!(name: "Test#{rand(1000)}, Person", type: 'Student', studio: studio, level: levels(:FS), age: ages(:A))
    
    # Create a PersonOption record with table assignment
    table = tables(:one)
    table.update!(option: option)
    person_option = PersonOption.create!(person: person, option: option, table: table)
    
    # Cleanup should keep the record but clear table_id
    assert_no_difference 'PersonOption.count' do
      result = PersonOption.cleanup_if_only_from_package(person_option)
      assert_not result # Should return false when kept
    end
    
    person_option.reload
    assert_nil person_option.table_id
  end
  
  test "cleanup_if_only_from_package handles nil person_option" do
    result = PersonOption.cleanup_if_only_from_package(nil)
    assert_not result
  end
  
  test "find_or_create_for_table_assignment creates new record" do
    option = billables(:two)  # This is an option
    person = people(:student_one)
    
    # Ensure no existing record
    PersonOption.where(person_id: person.id, option_id: option.id).destroy_all
    
    assert_difference 'PersonOption.count', 1 do
      person_option = PersonOption.find_or_create_for_table_assignment(
        person_id: person.id,
        option_id: option.id
      )
      assert_equal person, person_option.person
      assert_equal option, person_option.option
    end
  end
  
  test "find_or_create_for_table_assignment finds existing record" do
    person_option = person_options(:one)
    
    assert_no_difference 'PersonOption.count' do
      found = PersonOption.find_or_create_for_table_assignment(
        person_id: person_option.person_id,
        option_id: person_option.option_id
      )
      assert_equal person_option, found
    end
  end
end
