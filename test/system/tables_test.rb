require "application_system_test_case"

class TablesTest < ApplicationSystemTestCase
  setup do
    @table = tables(:one)
  end

  test "visiting the index" do
    visit tables_url
    assert_selector "h1", text: "Table Arrangement"
  end

  test "should create table" do
    visit tables_url
    click_on "New Table"

    fill_in "Row", with: 2
    fill_in "Col", with: 2
    fill_in "Number", with: 99
    fill_in "Size", with: 10
    click_on "Create Table"

    assert_text "Table was successfully created"
    # Should now be back at the index page after creation
    assert_selector "h1", text: "Table Arrangement"
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
    click_on "New Table"
    
    # The number field should be auto-populated with 6 (max + 1)
    number_field = find_field("Number")
    assert_equal "6", number_field.value
  end
end
