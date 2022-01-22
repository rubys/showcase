require "application_system_test_case"

class DancesTest < ApplicationSystemTestCase
  setup do
    @dance = dances(:one)
  end

  test "visiting the index" do
    visit dances_url
    assert_selector "h1", text: "Dances"
  end

  test "should create dance" do
    visit dances_url
    click_on "New dance"

    fill_in "Category", with: @dance.category
    fill_in "Name", with: @dance.name
    click_on "Create Dance"

    assert_text "Dance was successfully created"
    click_on "Back"
  end

  test "should update Dance" do
    visit dance_url(@dance)
    click_on "Edit this dance", match: :first

    fill_in "Category", with: @dance.category
    fill_in "Name", with: @dance.name
    click_on "Update Dance"

    assert_text "Dance was successfully updated"
    click_on "Back"
  end

  test "should destroy Dance" do
    visit dance_url(@dance)
    click_on "Destroy this dance", match: :first

    assert_text "Dance was successfully destroyed"
  end
end
