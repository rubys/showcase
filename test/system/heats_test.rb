require "application_system_test_case"

class HeatsTest < ApplicationSystemTestCase
  setup do
    @heat = heats(:one)
  end

  test "visiting the index" do
    visit heats_url
    assert_selector "h1", text: "Heats"
  end

  test "should create heat" do
    visit heats_url
    click_on "New heat"

    fill_in "Entry", with: @heat.entry_id
    fill_in "Number", with: @heat.number
    click_on "Create Heat"

    assert_text "Heat was successfully created"
    click_on "Back"
  end

  test "should update Heat" do
    visit heat_url(@heat)
    click_on "Edit this heat", match: :first

    fill_in "Entry", with: @heat.entry_id
    fill_in "Number", with: @heat.number
    click_on "Update Heat"

    assert_text "Heat was successfully updated"
    click_on "Back"
  end

  test "should destroy Heat" do
    visit heat_url(@heat)
    click_on "Destroy this heat", match: :first

    assert_text "Heat was successfully destroyed"
  end
end
