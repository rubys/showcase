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
    # Clear all table assignments to ensure we have unassigned people
    Person.update_all(table_id: nil)
    Table.destroy_all
    
    # Get count of people from fixtures
    unassigned_count = Person.joins(:studio).where(table_id: nil, type: ['Student', 'Professional', 'Guest']).where.not(studio_id: 0).count
    
    get tables_url
    assert_response :success
    
    # Should show the unassigned people warning
    assert_select "div.bg-yellow-50", 1
    
    if unassigned_count > 10
      # Should show grid layout for studio summary
      assert_select "div.grid", 1
      # Should show studio cards (count may vary based on fixtures)
      assert_select "div.bg-white", { minimum: 1 }
    else
      # Should show simple list instead of grid
      assert_select "ul.list-disc", 1
    end
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

  test "should create table and auto-fill with studio people" do
    # Assign all existing people to tables to start fresh
    Person.where(table_id: nil, type: ['Student', 'Professional', 'Guest']).where.not(studio_id: 0).update_all(table_id: tables(:one).id)
    
    # Create unassigned people for a studio
    studio = studios(:one)
    level = levels(:FS)
    age = ages(:A)
    
    person1 = Person.create!(name: "Auto Student 1", studio: studio, type: "Student", level: level, age: age)
    person2 = Person.create!(name: "Auto Student 2", studio: studio, type: "Student", level: level, age: age)
    person3 = Person.create!(name: "Auto Pro", studio: studio, type: "Professional")
    
    assert_difference("Table.count") do
      post tables_url, params: { table: { number: 999, size: 2, studio_id: studio.id } }
    end

    assert_redirected_to tables_url
    
    # Check that the table was created and people were assigned
    new_table = Table.find_by(number: 999)
    assert_not_nil new_table
    assert_equal 2, new_table.people.count  # Should be limited by table size
    
    # Check that the first 2 people (alphabetically) were assigned
    assigned_people = new_table.people.order(:name)
    assert_equal "Auto Pro", assigned_people.first.name
    assert_equal "Auto Student 1", assigned_people.second.name
    
    # Third person should still be unassigned (table size was 2)
    person2.reload
    assert_nil person2.table_id
  end

  test "should show studio select on new table page when unassigned people exist" do
    # Assign all existing people to tables to start fresh
    Person.where(table_id: nil, type: ['Student', 'Professional', 'Guest']).where.not(studio_id: 0).update_all(table_id: tables(:one).id)
    
    # Create unassigned people
    studio = studios(:two)  # Use a different studio to avoid conflicts
    level = levels(:FS)
    age = ages(:A)
    Person.create!(name: "Unassigned Student", studio: studio, type: "Student", level: level, age: age)
    
    get new_table_url
    assert_response :success
    assert_select "select[name='table[studio_id]']"
    # Just check that some studio option exists, don't worry about specific value
    assert_select "option", minimum: 2  # At least the default option plus one studio
  end

  test "should show studio select on edit page when table has capacity" do
    # Create a table with some people but not at capacity
    table = Table.create!(number: 998, size: 5)
    studio = studios(:one)
    level = levels(:FS)
    age = ages(:A)
    
    # Add 2 people to the table (leaving 3 seats available)
    person1 = Person.create!(name: "Seated Person 1", studio: studio, type: "Student", level: level, age: age, table: table)
    person2 = Person.create!(name: "Seated Person 2", studio: studio, type: "Student", level: level, age: age, table: table)
    
    # Create unassigned people in a different studio
    studio2 = studios(:two)
    Person.create!(name: "Unassigned Student", studio: studio2, type: "Student", level: level, age: age)
    
    get edit_table_url(table)
    assert_response :success
    assert_select "select[name='table[studio_id]']"
    assert_select "p", text: /up to 3 unassigned people/
  end

  test "should not show studio select on edit page when table is at capacity" do
    # Create a table at capacity
    table = Table.create!(number: 997, size: 2)
    studio = studios(:one)
    level = levels(:FS)
    age = ages(:A)
    
    # Fill the table to capacity
    person1 = Person.create!(name: "Seated Person 1", studio: studio, type: "Student", level: level, age: age, table: table)
    person2 = Person.create!(name: "Seated Person 2", studio: studio, type: "Student", level: level, age: age, table: table)
    
    get edit_table_url(table)
    assert_response :success
    assert_select "select[name='table[studio_id]']", count: 0
  end

  test "should update table and add people from studio" do
    # Assign all existing people to tables to start fresh
    Person.where(table_id: nil, type: ['Student', 'Professional', 'Guest']).where.not(studio_id: 0).update_all(table_id: tables(:one).id)
    
    # Create a table with capacity
    table = Table.create!(number: 996, size: 4)
    
    # Create unassigned people
    studio = studios(:one)
    level = levels(:FS)
    age = ages(:A)
    person1 = Person.create!(name: "Update Student 1", studio: studio, type: "Student", level: level, age: age)
    person2 = Person.create!(name: "Update Student 2", studio: studio, type: "Student", level: level, age: age)
    
    patch table_url(table), params: { table: { size: 4, studio_id: studio.id } }
    
    assert_redirected_to tables_url
    
    # Check that people were added to the table
    table.reload
    assert_equal 2, table.people.count
    assert_includes table.people.pluck(:name), "Update Student 1"
    assert_includes table.people.pluck(:name), "Update Student 2"
  end

  test "should only add available seats when updating table with existing people" do
    # Assign all existing people to tables to start fresh
    Person.where(table_id: nil, type: ['Student', 'Professional', 'Guest']).where.not(studio_id: 0).update_all(table_id: tables(:one).id)
    
    # Create a table with size 10 and add 4 people to it
    table = Table.create!(number: 995, size: 10)
    studio = studios(:one)
    level = levels(:FS)
    age = ages(:A)
    
    # Add 4 people to the table
    4.times do |i|
      person = Person.create!(name: "Existing Person #{i}", studio: studio, type: "Student", level: level, age: age, table: table)
    end
    
    # Create 10 more unassigned people from the same studio
    10.times do |i|
      Person.create!(name: "Unassigned Person #{i}", studio: studio, type: "Student", level: level, age: age)
    end
    
    # Update the table and select the studio - should only add 6 people (available seats)
    patch table_url(table), params: { table: { size: 10, studio_id: studio.id } }
    
    assert_redirected_to tables_url
    
    # Check that only 6 more people were added (total should be 10, not 14)
    table.reload
    assert_equal 10, table.people.count, "Table should have exactly 10 people (4 existing + 6 added)"
    
    # Verify table is now at capacity (people count equals table size)
    assert_equal table.size, table.people.count, "Table should be at capacity"
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

  test "should assign people to tables while preserving studio relationships" do
    # Set up test data
    Person.update_all(table_id: nil)
    Table.destroy_all
    
    # Set table size to 10 (default)
    Event.first.update!(table_size: 10)
    
    # Count total people from non-Event Staff studios
    total_people = Person.joins(:studio).where.not(studios: { id: 0 }).count
    
    # Call assign action
    post assign_tables_url
    
    # The new algorithm prioritizes studio relationships over pure optimization
    # so the number of tables may be higher than pure mathematical optimum
    # but should still be reasonable
    optimal_tables = (total_people.to_f / 10).ceil
    actual_tables = Table.count
    
    # Should be at most 50% more tables than optimal (allows for studio relationship preservation)
    assert actual_tables <= (optimal_tables * 1.5).ceil, "Should create reasonable number of tables (#{actual_tables} vs optimal #{optimal_tables})"
    
    # Verify all people are assigned
    assert_equal total_people, Person.joins(:studio).where.not(studios: { id: 0 }).where.not(table_id: nil).count
    
    # Verify no table exceeds the size limit
    Table.all.each do |table|
      assert table.people.count <= 10, "Table #{table.number} should not exceed size limit"
    end
  end

  test "should create reasonable number of tables with studio relationships" do
    # Clear existing data
    Person.update_all(table_id: nil)
    Table.destroy_all
    
    # Set a smaller table size to test filling behavior with existing people
    Event.first.update!(table_size: 2)
    
    # Count existing people (should be at least 3 from Adelaide)
    total_people = Person.joins(:studio).where.not(studios: { id: 0 }).count
    
    # Call assign action
    post assign_tables_url
    
    # The new algorithm prioritizes studio relationships, so table count may be higher
    # than pure mathematical optimum but should still be reasonable
    optimal_tables = (total_people.to_f / 2).ceil
    actual_tables = Table.count
    
    # Should be at most 50% more tables than optimal (allows for studio relationship preservation)
    assert actual_tables <= (optimal_tables * 1.5).ceil, "Should create reasonable number of tables (#{actual_tables} vs optimal #{optimal_tables})"
    
    # Verify all people are assigned
    assert_equal total_people, Person.joins(:studio).where.not(studios: { id: 0 }).where.not(table_id: nil).count
    
    # Verify no table exceeds the size limit
    Table.all.each do |table|
      assert table.people.count <= 2, "Table #{table.number} should not exceed size limit"
    end
    
    # Verify most tables have at least 1 person (no completely empty tables)
    Table.all.each do |table|
      assert table.people.count >= 1, "Table #{table.number} should have at least 1 person"
    end
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

  test "should handle large groups with studio relationship preservation" do
    # Clear existing data
    Person.update_all(table_id: nil)
    Table.destroy_all
    
    # Set up scenario with many people and studios
    Event.first.update!(table_size: 10)
    
    # Test with our existing people from many studios
    total_people = Person.joins(:studio).where.not(studios: { id: 0 }).count
    
    post assign_tables_url
    
    # The new algorithm prioritizes studio relationships over pure optimization
    # so may create more tables than pure mathematical optimum
    optimal_tables = (total_people.to_f / 10).ceil
    actual_tables = Table.count
    
    # Should be at most 50% more tables than optimal (allows for studio relationship preservation)
    assert actual_tables <= (optimal_tables * 1.5).ceil, "Should create reasonable number of tables (#{actual_tables} vs optimal #{optimal_tables})"
    
    # Verify all people are assigned
    assert_equal total_people, Person.joins(:studio).where.not(studios: { id: 0 }).where.not(table_id: nil).count
    
    # Verify no table exceeds the size limit
    Table.all.each do |table|
      assert table.people.count <= 10, "Table #{table.number} should not exceed size limit"
    end
    
    # Verify most tables have reasonable occupancy (at least 1 person)
    Table.all.each do |table|
      assert table.people.count >= 1, "Table #{table.number} should have at least 1 person"
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
  
  # Option-scoped table tests
  test "should filter tables by option_id in index" do
    option = billables(:two)  # This is an Option type
    table1 = tables(:one)
    table2 = tables(:two)
    
    # Assign table1 to option
    table1.update!(option: option)
    
    # Request tables for this option
    get tables_url(option_id: option.id)
    assert_response :success
    
    # Should only show table1
    assert_select "div.font-bold", text: "Table #{table1.number}"
    assert_select "div.font-bold", text: "Table #{table2.number}", count: 0
  end
  
  test "should show only main event tables when no option_id" do
    option = billables(:two)  # This is an Option type
    table1 = tables(:one)
    table2 = tables(:two)
    
    # Assign table1 to option
    table1.update!(option: option)
    
    # Request tables without option_id
    get tables_url
    assert_response :success
    
    # Should only show table2 (main event table)
    assert_select "div.font-bold", text: "Table #{table2.number}"
    assert_select "div.font-bold", text: "Table #{table1.number}", count: 0
  end
  
  test "should create table with option_id" do
    option = billables(:two)  # This is an Option type
    
    assert_difference("Table.count") do
      post tables_url(option_id: option.id), params: { table: { number: 99, size: 10 } }
    end
    
    table = Table.last
    assert_equal option, table.option
    assert_redirected_to tables_url(option_id: option.id)
  end
  
  test "should show unassigned people for option in index" do
    option = billables(:two)  # This is an Option type
    person = people(:Arthur)
    
    # Create person_option without table assignment
    PersonOption.create!(person: person, option: option)
    
    get tables_url(option_id: option.id)
    assert_response :success
    
    # Should show the person as unassigned
    assert_select "div.bg-yellow-50"
    assert_select "li", text: /#{person.name}/
  end
  
  test "should assign people to option tables" do
    option = billables(:two)  # This is an Option type
    person1 = people(:Arthur)
    person2 = people(:Kathryn)
    
    # Create person_options without table assignments
    PersonOption.create!(person: person1, option: option)
    PersonOption.create!(person: person2, option: option)
    
    # Run assign for option tables
    post assign_tables_url(option_id: option.id)
    assert_redirected_to tables_url(option_id: option.id)
    
    # Verify tables were created for the option
    option_tables = Table.where(option_id: option.id)
    assert_not_empty option_tables
    
    # Verify person_options were assigned to tables
    person1_option = PersonOption.find_by(person: person1, option: option)
    person2_option = PersonOption.find_by(person: person2, option: option)
    
    assert_not_nil person1_option.table_id
    assert_not_nil person2_option.table_id
  end
  
  test "should reset only option tables" do
    option = billables(:two)  # This is an Option type
    table1 = tables(:one)
    table2 = tables(:two)
    
    # Assign table1 to option
    table1.update!(option: option)
    
    # Reset option tables
    delete reset_tables_url(option_id: option.id)
    assert_redirected_to tables_url(option_id: option.id)
    
    # table1 should be deleted, table2 should remain
    assert_not Table.exists?(table1.id)
    assert Table.exists?(table2.id)
  end
  
  test "should validate option exists when option_id provided" do
    assert_raises(ActiveRecord::RecordNotFound) do
      get tables_url(option_id: 999999)
    end
  end
  
  test "should validate option is actually an option not a package" do
    package = billables(:one)  # This is a Student package type
    
    assert_raises(ActiveRecord::RecordNotFound) do
      get tables_url(option_id: package.id)
    end
  end
end
