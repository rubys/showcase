require "test_helper"

class BillableTest < ActiveSupport::TestCase
  test "option should have many tables" do
    option = billables(:two)  # This is an Option type
    table1 = tables(:one)
    table2 = tables(:two)
    
    table1.update!(option: option)
    table2.update!(option: option)
    
    assert_includes option.tables, table1
    assert_includes option.tables, table2
  end
  
  test "package should have many tables" do
    package = billables(:one)  # This is a Student package type
    table = tables(:one)
    
    # Packages can also have tables associated
    table.update!(option: package)
    
    assert_includes package.tables, table
  end
end
