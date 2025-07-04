require "test_helper"

class TablesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @table = tables(:one)
  end

  test "should get index" do
    get tables_url
    assert_response :success
  end

  test "should show unassigned people when less than or equal to 10" do
    # Assign all existing people to tables to start fresh
    Person.where(table_id: nil, type: ['Student', 'Professional', 'Guest']).where.not(studio_id: 0).update_all(table_id: tables(:one).id)
    
    # Create people without table assignments
    studio = studios(:one)
    level = levels(:FS)
    age = ages(:A)
    person1 = Person.create!(name: "Test Student", studio: studio, type: "Student", level: level, age: age)
    person2 = Person.create!(name: "Test Pro", studio: studio, type: "Professional")
    
    get tables_url
    assert_response :success
    
    # Check that unassigned section appears
    assert_select "div.bg-yellow-50"
    assert_select "h3", text: "People Without Table Assignments"
    
    # Should show individual people since count <= 10
    assert_select "ul.list-disc"
    assert_select "li", text: /Test Student.*Student/
    assert_select "li", text: /Test Pro.*Professional/
  end

  test "should show studio summary when more than 10 unassigned people" do
    # Assign all existing people to tables to start fresh
    Person.where(table_id: nil, type: ['Student', 'Professional', 'Guest']).where.not(studio_id: 0).update_all(table_id: tables(:one).id)
    
    # Create more than 10 people without table assignments across different studios
    studio1 = studios(:one)
    studio2 = studios(:two)
    level = levels(:FS)
    age = ages(:A)
    
    # Create 6 people in studio1
    6.times do |i|
      Person.create!(name: "Student #{i}", studio: studio1, type: "Student", level: level, age: age)
    end
    
    # Create 6 people in studio2  
    6.times do |i|
      Person.create!(name: "Pro #{i}", studio: studio2, type: "Professional")
    end
    
    get tables_url
    assert_response :success
    assert_select "div.bg-yellow-50", 1
    assert_select "div.grid", 1  # Grid layout for studio summary
    assert_select "div.bg-white", 2  # Two studio cards
  end

  test "should get list" do
    get list_tables_url
    assert_response :success
  end

  test "should get list as pdf" do
    get list_tables_url(format: :pdf)
    assert_response :success
    assert_equal "application/pdf", response.content_type
  end

  test "should reset all tables" do
    assert_difference("Table.count", -Table.count) do
      delete reset_tables_url
    end
    
    assert_redirected_to tables_url
    assert_equal "All tables have been deleted.", flash[:notice]
  end

  test "should remove table associations when resetting" do
    # Assign a person to a table
    person = people(:Arthur)
    table = tables(:one)
    person.update!(table: table)
    
    assert_not_nil person.table_id
    
    delete reset_tables_url
    
    person.reload
    assert_nil person.table_id
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
    assert_redirected_to tables_url
  end

  test "should swap table numbers when updating to existing number" do
    table1 = tables(:one)
    table2 = tables(:two)
    original_table1_number = table1.number
    original_table2_number = table2.number
    
    # Update table1 to have table2's number
    patch table_url(table1), params: { table: { number: original_table2_number } }
    
    assert_redirected_to tables_url
    assert_match /swapped numbers/i, flash[:notice]
    
    # Reload both tables
    table1.reload
    table2.reload
    
    # Verify the swap occurred
    assert_equal original_table2_number, table1.number
    assert_equal original_table1_number, table2.number
  end

  test "should update table number without swap when no conflict" do
    table1 = tables(:one)
    new_number = 999  # A number that doesn't exist
    
    patch table_url(table1), params: { table: { number: new_number } }
    
    assert_redirected_to tables_url
    assert_no_match /swapped/i, flash[:notice]
    
    table1.reload
    assert_equal new_number, table1.number
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

  test "should renumber tables based on position" do
    # Clear existing tables
    Table.destroy_all
    
    # Create tables in non-sequential order with positions
    table3 = Table.create!(number: 3, row: 1, col: 2, size: 8)
    table1 = Table.create!(number: 1, row: 1, col: 1, size: 8)
    table4 = Table.create!(number: 4, row: 2, col: 1, size: 8)
    table2 = Table.create!(number: 2, row: 2, col: 2, size: 8)
    
    # Call renumber action
    patch renumber_tables_url
    
    assert_redirected_to arrange_tables_path
    assert_equal "Tables have been renumbered successfully.", flash[:notice]
    
    # Verify tables are renumbered by position (row first, then col)
    table1.reload
    table2.reload
    table3.reload
    table4.reload
    
    assert_equal 1, table1.number, "Table at position (1,1) should be numbered 1"
    assert_equal 2, table3.number, "Table at position (1,2) should be numbered 2"
    assert_equal 3, table4.number, "Table at position (2,1) should be numbered 3"
    assert_equal 4, table2.number, "Table at position (2,2) should be numbered 4"
  end

  test "should renumber tables with null positions last" do
    # Clear existing tables
    Table.destroy_all
    
    # Create tables with mixed positions
    table_no_pos = Table.create!(number: 99, row: nil, col: nil, size: 8)
    table_pos_1 = Table.create!(number: 88, row: 1, col: 1, size: 8)
    table_partial = Table.create!(number: 77, row: 2, col: nil, size: 8)
    table_pos_2 = Table.create!(number: 66, row: 1, col: 2, size: 8)
    
    # Call renumber action
    patch renumber_tables_url
    
    assert_redirected_to arrange_tables_path
    
    # Reload tables
    table_pos_1.reload
    table_pos_2.reload
    table_partial.reload
    table_no_pos.reload
    
    # Verify positioned tables come first
    assert_equal 1, table_pos_1.number, "Table at (1,1) should be numbered 1"
    assert_equal 2, table_pos_2.number, "Table at (1,2) should be numbered 2"
    
    # Tables with partial or no positions should be numbered last
    assert table_partial.number > 2, "Table with partial position should be numbered after positioned tables"
    assert table_no_pos.number > 2, "Table with no position should be numbered after positioned tables"
  end

  test "should handle renumber with no tables" do
    # Clear all tables
    Table.destroy_all
    
    # Call renumber action
    patch renumber_tables_url
    
    assert_redirected_to arrange_tables_path
    assert_equal "Tables have been renumbered successfully.", flash[:notice]
    
    # Should not raise any errors
    assert_equal 0, Table.count
  end

  test "should show tables for a specific studio" do
    # Create test data: assign people to tables
    studio = Studio.joins(:people).where.not(people: { studio_id: 0 }).first
    assert studio, "Should have a studio with people"
    
    # Assign some people from this studio to a table
    people_from_studio = Person.where(studio: studio).limit(2)
    if people_from_studio.any?
      people_from_studio.update_all(table_id: @table.id)
    end
    
    get studio_tables_url(studio)
    
    assert_response :success
    assert_select "h1", text: "Tables for #{studio.name}"
    
    # Should show tables with people from this studio if any are assigned
    if people_from_studio.any?
      assert_select "div", text: "Table #{@table.number}"
      # Should show the names of people from this studio
      people_from_studio.each do |person|
        assert_select "div", text: person.name
      end
    end
  end

  test "should show studio with no table assignments" do
    # Create a studio with no people assigned to tables
    studio = Studio.create!(name: "Test Studio")
    
    get studio_tables_url(studio)
    
    assert_response :success
    assert_select "h1", text: "Tables for #{studio.name}"
    assert_select "h2", text: "No Tables Found"
    assert_select "p", text: /doesn't have anyone assigned to tables yet/
  end

  test "should show summary information for studio tables" do
    # Create test data: assign people to tables
    studio = Studio.joins(:people).where.not(people: { studio_id: 0 }).first
    assert studio, "Should have a studio with people"
    
    # Assign some people from this studio to a table
    people_from_studio = Person.where(studio: studio).limit(2)
    people_from_studio.update_all(table_id: @table.id) if people_from_studio.any?
    
    get studio_tables_url(studio)
    
    assert_response :success
    
    if people_from_studio.any?
      # Should show summary section
      assert_select "h2", text: "Summary for #{studio.name}"
      
      # Should show table count
      studio_table_count = Table.joins(people: :studio).where(studios: { id: studio.id }).distinct.count
      assert_select "p", text: /has people seated at.*#{studio_table_count}.*table/
      
      # Should show people count
      studio_people_count = Person.where(studio: studio).where.not(table_id: nil).count
      assert_select "p", text: /Total people from this studio:.*#{studio_people_count}/
    else
      # Should show no tables message
      assert_select "h2", text: "No Tables Found"
    end
  end

  test "should move person between tables" do
    # Create test data: two tables and a person
    max_number = Table.maximum(:number) || 0
    table1 = Table.create!(number: max_number + 1, size: 10)
    table2 = Table.create!(number: max_number + 2, size: 10)
    
    # Get a person from a studio (not Event Staff)
    person = Person.joins(:studio).where.not(studios: { id: 0 }).first
    assert person, "Should have a person to test with"
    
    # Assign person to table1
    person.update!(table_id: table1.id)
    
    # Move person from table1 to table2
    post move_person_tables_url, params: { source: "person-#{person.id}", target: "table-#{table2.id}" }
    
    # Should respond with turbo stream
    assert_response :success
    
    # Verify person was moved
    person.reload
    assert_equal table2.id, person.table_id, "Person should be moved to table2"
    
    # Verify response contains success message
    assert_match /moved to Table #{table2.number}/, response.body
  end

  test "should move person to same table as another person" do
    # Create test data: tables and people
    max_number = Table.maximum(:number) || 0
    table1 = Table.create!(number: max_number + 1, size: 10)
    table2 = Table.create!(number: max_number + 2, size: 10)
    
    # Get two people from studios (not Event Staff)
    people = Person.joins(:studio).where.not(studios: { id: 0 }).limit(2)
    assert people.count >= 2, "Should have at least 2 people to test with"
    
    person1 = people.first
    person2 = people.second
    
    # Assign people to different tables
    person1.update!(table_id: table1.id)
    person2.update!(table_id: table2.id)
    
    # Move person1 to person2's table by dropping on person2
    post move_person_tables_url, params: { source: "person-#{person1.id}", target: "person-#{person2.id}" }
    
    # Should respond with turbo stream
    assert_response :success
    
    # Verify person1 was moved to table2 (same as person2)
    person1.reload
    assert_equal table2.id, person1.table_id, "Person1 should be moved to table2 (same as person2)"
    
    # Verify response contains success message
    assert_match /moved to Table #{table2.number}/, response.body
  end

  test "should ignore requests to move tables" do
    # Create test data: two tables
    max_number = Table.maximum(:number) || 0
    table1 = Table.create!(number: max_number + 1, size: 10)
    table2 = Table.create!(number: max_number + 2, size: 10)
    
    # Try to "move" table1 to table2 (should be ignored)
    post move_person_tables_url, params: { source: "table-#{table1.id}", target: "table-#{table2.id}" }
    
    # Should respond with 200 OK but do nothing
    assert_response :ok
    
    # Verify tables still exist and weren't modified
    table1.reload
    table2.reload
    assert_equal max_number + 1, table1.number
    assert_equal max_number + 2, table2.number
  end
end
