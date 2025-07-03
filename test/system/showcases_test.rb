require "application_system_test_case"

class ShowcasesTest < ApplicationSystemTestCase
  setup do
    @showcase = showcases(:one)
  end

  test "visiting the index" do
    visit showcases_url
    assert_selector "h1", text: "Showcases"
  end

  test "should create showcase" do
    skip "Geocoding API calls cause flaky test failures"
    visit showcases_url
    click_on "New showcase"

    fill_in "Key", with: @showcase.key+'2'
    fill_in "Name", with: @showcase.name+'2'
    select @showcase.location.name, from: "Location"
    fill_in "Year", with: @showcase.year
    click_on "Create Showcase"

    assert_text "MyString2 was successfully created"
    click_on "Back"
  end

  test "should update Showcase" do
    skip "Geocoding API calls cause flaky test failures"
    visit showcase_url(@showcase)
    click_on "Edit this showcase", match: :first

    fill_in "Key", with: @showcase.key
    fill_in "Name", with: @showcase.name
    select @showcase.location.name, from: "Location"
    fill_in "Year", with: @showcase.year
    click_on "Update Showcase"

    assert_text "MyString was successfully updated"
    click_on "Back"
  end

  test "should destroy Showcase" do
    visit showcase_url(@showcase)
    click_on "Destroy this showcase", match: :first

    assert_text "MyString was successfully destroyed"
  end
end
