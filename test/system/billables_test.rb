require "application_system_test_case"

class BillablesTest < ApplicationSystemTestCase
  setup do
    @billable = billables(:one)
  end

  test "visiting the index" do
    visit billables_url
    assert_selector "h1", text: "Billable Items"
  end

  test "should create billable" do
    visit billables_url
    click_on "New package"

    fill_in "Price", with: @billable.price
    fill_in "Name", with: @billable.name + '2'
    select @billable.type, from: 'Type'
    click_on "Create package"

    assert_text "#{@billable.name}2 was successfully created"
  end

  test "should update Billable" do
    visit billable_url(@billable)
    click_on "Edit this billable", match: :first

    fill_in "Price", with: @billable.price
    fill_in "Name", with: @billable.name
    select @billable.type, from: 'Type'
    click_on "Update package"

    assert_text "#{@billable.name} was successfully updated"
  end

  test "should destroy Billable" do
    visit billable_url(@billable)
    click_on "Destroy this billable", match: :first

    assert_text "#{@billable.name} was successfully removed"
  end
end
