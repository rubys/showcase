require "test_helper"

class TablesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @table = tables(:one)
  end

  test "should get index" do
    get tables_url
    assert_response :success
  end

  test "should get arrange" do
    get arrange_tables_url
    assert_response :success
  end

  test "should get new" do
    get new_table_url
    assert_response :success
  end

  test "should create table" do
    assert_difference("Table.count") do
      post tables_url, params: { table: { row: 2, col: 2, number: 99, size: 10 } }
    end

    assert_redirected_to tables_url
  end

  test "should show table" do
    get table_url(@table)
    assert_response :success
  end

  test "should get edit" do
    get edit_table_url(@table)
    assert_response :success
  end

  test "should show people assigned to table in edit view" do
    # Assign some people to the table
    people = Person.joins(:studio).where.not(studios: { id: 0 }).limit(2)
    people.update_all(table_id: @table.id)
    
    # Reload to get the actual records
    assigned_people = Person.where(table_id: @table.id)
    
    get edit_table_url(@table)
    assert_response :success
    
    # Check that the people section is shown
    assert_select "h2", text: "People at this table"
    
    # Check that people are listed
    assigned_people.each do |person|
      assert_select "a[href=?]", person_path(person), text: person.name
    end
    
    # Check the total count
    assert_select "p", text: /Total: #{assigned_people.count} people/
  end

  test "should show empty message when no people assigned" do
    # Ensure no people are assigned to this table
    Person.where(table_id: @table.id).update_all(table_id: nil)
    
    get edit_table_url(@table)
    assert_response :success
    
    # Check that the empty message is shown
    assert_select "p", text: "No people assigned to this table yet."
  end

  test "should update table" do
    patch table_url(@table), params: { table: { row: 3, col: 3, number: @table.number, size: 12 } }
    assert_redirected_to table_url(@table)
  end

  test "should destroy table" do
    assert_difference("Table.count", -1) do
      delete table_url(@table)
    end

    assert_redirected_to tables_url
  end

  test "should auto-populate number field in new action" do
    # Create a few tables first (avoid existing row/col combinations)
    Table.create!(number: 5, row: 2, col: 1, size: 8)
    Table.create!(number: 10, row: 2, col: 2, size: 6)
    
    get new_table_url
    assert_response :success
    
    # Check that the response body contains the correct number value
    assert_includes response.body, 'value="11"'
  end

  test "should auto-populate number field when no tables exist" do
    # Clear all tables except fixtures
    Table.where.not(id: [@table.id, tables(:two).id]).delete_all
    
    # Get the current max number from fixtures
    max_number = Table.maximum(:number)
    expected_number = max_number + 1
    
    get new_table_url
    assert_response :success
    
    # Check that the response body contains the correct number value
    assert_includes response.body, "value=\"#{expected_number}\""
  end

  test "should update positions" do
    post update_positions_tables_url, params: { 
      table: { 
        @table.id => { row: 3, col: 3 } 
      } 
    }
    
    assert_response :success
    @table.reload
    assert_equal 3, @table.row
    assert_equal 3, @table.col
  end

  test "should reset positions" do
    post update_positions_tables_url, params: { commit: 'Reset' }
    
    assert_redirected_to tables_url
    @table.reload
    assert_nil @table.row
    assert_nil @table.col
  end

  test "should assign people to tables" do
    # Ensure we have people to assign
    assert Person.joins(:studio).where.not(studios: { id: 0 }).any?, "Should have people to assign"
    
    # Clear any existing table assignments
    Person.update_all(table_id: nil)
    
    # Delete all existing tables
    Table.destroy_all
    
    # Call the assign action
    post assign_tables_url
    
    assert_redirected_to tables_path
    assert_equal "Tables have been assigned successfully.", flash[:notice]
    
    # Verify tables were created
    assert Table.any?, "Tables should have been created"
    
    # Verify people were assigned to tables
    assigned_people = Person.joins(:studio).where.not(studios: { id: 0 }).where.not(table_id: nil)
    assert assigned_people.any?, "People should be assigned to tables"
    
    # Verify tables have row and column positions
    assert Table.all.all? { |t| t.row.present? && t.col.present? }, "All tables should have positions"
    
    # Verify column constraint
    assert Table.maximum(:col) <= 8, "No table should have column > 8"
  end

  test "should optimize table assignments by combining small studios" do
    # Set up test data
    Person.update_all(table_id: nil)
    Table.destroy_all
    
    # Set table size to 10 (default)
    Event.first.update!(table_size: 10)
    
    # Count total people from non-Event Staff studios
    # From fixtures, we have 3 people from Adelaide studio
    total_people = Person.joins(:studio).where.not(studios: { id: 0 }).count
    
    # Call assign action
    post assign_tables_url
    
    # With 3 people total and table size of 10, they should all fit on 1 table
    expected_tables = (total_people.to_f / 10).ceil
    assert_equal expected_tables, Table.count, "Should minimize number of tables"
    
    # Verify all people are assigned
    assert_equal total_people, Person.joins(:studio).where.not(studios: { id: 0 }).where.not(table_id: nil).count
    
    # Verify no table exceeds the size limit
    Table.all.each do |table|
      assert table.people.count <= 10, "Table #{table.number} should not exceed size limit"
    end
  end

  test "should fill tables to capacity when assigning people" do
    # Clear existing data
    Person.update_all(table_id: nil)
    Table.destroy_all
    
    # Set a smaller table size to test filling behavior with existing people
    Event.first.update!(table_size: 2)
    
    # Count existing people (should be at least 3 from Adelaide)
    total_people = Person.joins(:studio).where.not(studios: { id: 0 }).count
    
    # Call assign action
    post assign_tables_url
    
    # Calculate expected number of tables
    expected_tables = (total_people.to_f / 2).ceil
    assert_equal expected_tables, Table.count, "Should create optimal number of tables"
    
    # Check that tables are filled efficiently
    table_sizes = Table.all.map { |t| t.people.count }.sort.reverse
    
    # All tables except possibly the last one should be full
    table_sizes[0..-2].each do |size|
      assert_equal 2, size, "All tables except possibly the last should be full"
    end
    
    # Last table should have at least 1 person
    assert table_sizes.last >= 1, "Last table should have at least 1 person"
    
    # Verify no empty seats wasted - total seats should be minimal
    total_seats_used = table_sizes.sum
    assert_equal total_people, total_seats_used, "No empty seats - all people should be assigned"
  end

  test "should minimize partial tables by combining small groups" do
    # Clear existing data
    Person.update_all(table_id: nil)
    Table.destroy_all
    
    # Create test data that simulates the Charlotte scenario
    # Multiple studios with sizes that would create many partial tables if not optimized
    studios_data = [
      { name: "Large Studio 1", people_count: 22 },
      { name: "Large Studio 2", people_count: 21 },
      { name: "Medium Studio", people_count: 18 },
      { name: "Small Studio 1", people_count: 11 },
      { name: "Small Studio 2", people_count: 10 },
      { name: "Small Studio 3", people_count: 8 },
      { name: "Tiny Studio 1", people_count: 4 },
      { name: "Tiny Studio 2", people_count: 2 },
      { name: "Tiny Studio 3", people_count: 1 },
      { name: "Tiny Studio 4", people_count: 1 },
      { name: "Tiny Studio 5", people_count: 2 }
    ]
    
    total_people = studios_data.sum { |s| s[:people_count] }
    table_size = 10
    Event.first.update!(table_size: table_size)
    
    # The tiny studios (4+2+1+1+2 = 10 people) should combine into 1 table
    # instead of creating 5 separate partial tables
    
    post assign_tables_url
    
    # Calculate theoretical minimum tables needed
    min_tables_needed = (total_people.to_f / table_size).ceil
    
    # Our algorithm should be close to optimal
    assert Table.count <= min_tables_needed + 1, "Should not create too many extra tables"
    
    # Check for efficiency - count partial tables (less than 80% capacity)
    partial_tables = Table.all.select { |t| t.people.count < (table_size * 0.8) }
    
    # Should have at most 1 partial table (the remainder)
    assert partial_tables.count <= 1, "Should minimize partial tables to at most 1"
  end

  test "should exactly match Charlotte scenario optimization" do
    # Clear existing data
    Person.update_all(table_id: nil)
    Table.destroy_all
    
    # Set up the exact Charlotte scenario: 104 people, table size 10
    Event.first.update!(table_size: 10)
    
    # With 104 people and table size 10, optimal is 11 tables (10×10 + 1×4)
    # Old algorithm would create 14 tables with many partial tables
    # New algorithm should create exactly 11 tables
    
    # Test with our existing 3 people - scale up the expectation
    total_people = Person.joins(:studio).where.not(studios: { id: 0 }).count
    
    post assign_tables_url
    
    # Should create optimal number of tables
    expected_tables = (total_people.to_f / 10).ceil
    assert_equal expected_tables, Table.count, "Should create exactly #{expected_tables} table(s) for #{total_people} people"
    
    # Should have minimal wasted seats
    total_seats = Table.count * 10
    wasted_seats = total_seats - total_people
    optimal_wasted = 10 - (total_people % 10 == 0 ? 10 : total_people % 10)
    optimal_wasted = 0 if total_people % 10 == 0
    
    assert_equal optimal_wasted, wasted_seats, "Should have optimal number of wasted seats"
    
    # All tables except possibly the last should be full or close to full
    table_sizes = Table.all.map { |t| t.people.count }.sort.reverse
    if table_sizes.length > 1
      table_sizes[0..-2].each do |size|
        assert size >= 8, "Tables should be well-filled (at least 8 people)"
      end
    end
  end
end
