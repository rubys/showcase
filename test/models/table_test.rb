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
end
