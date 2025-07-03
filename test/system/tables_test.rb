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

  test "should show table size form in index view" do
    visit tables_url
    
    # Should show the table size form container
    assert_selector "div.mt-6.p-4.bg-gray-50.rounded-lg"
    
    # Should show the form with auto-submit controller
    assert_selector "form[data-controller='auto-submit']"
    
    # Should show the label and input field
    assert_selector "label", text: "Default Table Size:"
    assert_selector "input[type='number'][name='event[table_size]']"
    
    # Should show the helper text
    assert_selector "span.text-sm.text-gray-500", text: "people per table"
  end

  test "should display default table size value of 10 when table_size is nil" do
    # Set table_size to nil
    Event.first.update(table_size: nil)
    
    visit tables_url
    
    # Should show default value of 10
    table_size_field = find_field("event[table_size]")
    assert_equal "10", table_size_field.value
  end

  test "should display default table size value of 10 when table_size is 0" do
    # Set table_size to 0
    Event.first.update(table_size: 0)
    
    visit tables_url
    
    # Should show default value of 10
    table_size_field = find_field("event[table_size]")
    assert_equal "10", table_size_field.value
  end

  test "should display actual table size value when set" do
    # Set table_size to a specific value
    Event.first.update(table_size: 8)
    
    visit tables_url
    
    # Should show the actual value
    table_size_field = find_field("event[table_size]")
    assert_equal "8", table_size_field.value
  end

  test "should have proper form styling and attributes" do
    visit tables_url
    
    # Should have proper form styling
    assert_selector "form.contents"
    
    # Should have proper input styling
    assert_selector "input.block.shadow.rounded-md.border.border-gray-200.outline-none.px-3.py-2.w-20.text-sm"
    
    # Should have proper label styling
    assert_selector "label.text-sm.font-medium.text-gray-700"
    
    # Should have min attribute set to 1
    table_size_field = find_field("event[table_size]")
    assert_equal "1", table_size_field["min"]
  end

  test "should have flexbox layout for form elements" do
    visit tables_url
    
    # Should have flex container
    assert_selector "div.flex.items-center.gap-3"
    
    # Should contain label, input, and helper text in flex layout
    flex_container = find("div.flex.items-center.gap-3")
    assert flex_container.has_selector?("label")
    assert flex_container.has_selector?("input")
    assert flex_container.has_selector?("span.text-sm.text-gray-500")
  end

  test "should position table size form below action buttons" do
    visit tables_url
    
    # Should have action buttons first - find the specific one with the links
    action_buttons = find("div.flex.gap-3", text: "Arrange Tables")
    assert action_buttons.has_link?("Arrange Tables")
    assert action_buttons.has_link?("New table")
    
    # Should have table size form after action buttons
    table_size_form = find("div.mt-6.p-4.bg-gray-50.rounded-lg")
    assert table_size_form.has_selector?("form[data-controller='auto-submit']")
    
    # Verify order by checking that form comes after buttons in DOM
    buttons_position = page.evaluate_script("document.querySelector('div.flex.gap-3').getBoundingClientRect().bottom")
    form_position = page.evaluate_script("document.querySelector('div.mt-6.p-4.bg-gray-50.rounded-lg').getBoundingClientRect().top")
    
    assert form_position > buttons_position, "Table size form should be positioned below action buttons"
  end
end
