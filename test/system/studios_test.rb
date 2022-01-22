require "application_system_test_case"

class StudiosTest < ApplicationSystemTestCase
  setup do
    @studio = studios(:one)
  end

  test "visiting the index" do
    visit studios_url
    assert_selector "h1", text: "Studios"
  end

  test "should create studio" do
    visit studios_url
    click_on "New studio"

    fill_in "Name", with: @studio.name
    click_on "Create Studio"

    assert_text "Studio was successfully created"
    click_on "Back"
  end

  test "should update Studio" do
    visit studio_url(@studio)
    click_on "Edit this studio", match: :first

    fill_in "Name", with: @studio.name
    click_on "Update Studio"

    assert_text "Studio was successfully updated"
    click_on "Back"
  end

  test "should destroy Studio" do
    visit studio_url(@studio)
    click_on "Destroy this studio", match: :first

    assert_text "Studio was successfully destroyed"
  end
end
