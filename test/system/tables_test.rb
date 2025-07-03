require "application_system_test_case"

class TablesTest < ApplicationSystemTestCase
  setup do
    @table = tables(:one)
  end

  test "visiting the index" do
    visit tables_url
    assert_selector "h1", text: "Tables"
  end

  test "visiting the arrange page" do
    visit arrange_tables_url
    assert_selector "h1", text: "Arrange Tables"
  end

  test "should create table" do
    visit tables_url
    click_on "New table"

    fill_in "Row", with: 2
    fill_in "Col", with: 2
    fill_in "Number", with: 99
    fill_in "Size", with: 10
    click_on "Create Table"

    assert_text "Table was successfully created"
    # Should now be back at the index page after creation
    assert_selector "h1", text: "Tables"
  end

  test "should update Table" do
    visit table_url(@table)
    click_on "Edit this table", match: :first

    fill_in "Row", with: 3
    fill_in "Col", with: 3
    fill_in "Number", with: @table.number
    fill_in "Size", with: 12
    click_on "Update Table"

    assert_text "Table was successfully updated"
    click_on "Back"
  end

  test "should destroy Table" do
    visit table_url(@table)
    click_on "Destroy this table", match: :first

    assert_text "Table was successfully destroyed"
  end

  test "should auto-populate number field in new form" do
    # Create a table with number 5 first (avoid existing row/col combinations)
    Table.create!(number: 5, row: 2, col: 1, size: 8)
    
    visit tables_url
    click_on "New table"
    
    # The number field should be auto-populated with 6 (max + 1)
    number_field = find_field("Number")
    assert_equal "6", number_field.value
  end

  test "should navigate between index and arrange views" do
    visit tables_url
    assert_selector "h1", text: "Tables"
    
    # Navigate to arrange view
    click_on "Arrange Tables"
    assert_selector "h1", text: "Arrange Tables"
    
    # Navigate back to index
    click_on "Back to Tables"
    assert_selector "h1", text: "Tables"
  end

  test "should show table list in grid view" do
    visit tables_url
    
    # Should show table information in a grid format
    assert_selector "#grid"
    assert_selector "div.font-bold", text: "Table #{@table.number}"
    
    # Should show table name/studio information
    assert_selector "div.text-sm", text: @table.name
  end

  test "should show draggable table grid in arrange view" do
    visit arrange_tables_url
    
    # Should show the grid for drag-and-drop
    assert_selector "#grid"
    assert_selector "div[draggable='true']"
    
    # Should show table information in draggable format
    assert_selector "div", text: "Table #{@table.number}"
    
    # Should have save and reset buttons
    assert_selector "button", text: "Save"
    assert_selector "input[value='Reset']"
  end

  test "should make tables clickable in index view" do
    visit tables_url
    
    # Should show clickable table links
    assert_selector "a[href='#{table_path(@table)}']"
    
    # Click on a table and verify it goes to show page
    click_on "Table #{@table.number}"
    
    # Should be on the show page now
    assert_selector "h1", text: "Showing table"
    assert_text "Number:"
    assert_text @table.number.to_s
  end

  test "should have hover effects on table links" do
    visit tables_url
    
    # Should have hover CSS classes
    assert_selector "a.hover\\:bg-blue-100"
    assert_selector "a.cursor-pointer"
    
    # Should have proper styling classes
    assert_selector "a.p-2.border.rounded.bg-gray-50"
  end

  test "should maintain grid layout with positioned tables" do
    visit tables_url
    
    # Should have CSS grid layout
    assert_selector "#grid[style*='display: grid']"
    assert_selector "#grid[style*='grid-template-columns']"
    
    # Tables with row/col should have grid positioning
    if @table.row && @table.col
      assert_selector "a[style*='grid-row:#{@table.row}']"
      assert_selector "a[style*='grid-column:#{@table.col}']"
    end
  end

  test "should handle tables without grid positions" do
    # Create a table without row/col positioning
    table_without_position = Table.create!(number: 99, size: 6)
    
    visit tables_url
    
    # Should still show the table as a clickable link
    assert_selector "a[href='#{table_path(table_without_position)}']"
    assert_selector "div.font-bold", text: "Table #{table_without_position.number}"
    
    # Should not have grid positioning styles
    assert_no_selector "a[href='#{table_path(table_without_position)}'][style*='grid-row']"
    assert_no_selector "a[href='#{table_path(table_without_position)}'][style*='grid-column']"
  end
end
