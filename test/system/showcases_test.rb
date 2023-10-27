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
    visit showcases_url
    click_on "New showcase"

    fill_in "Key", with: @showcase.key
    fill_in "Name", with: @showcase.name
    fill_in "Location", with: @showcase.location_id
    fill_in "Year", with: @showcase.year
    click_on "Create Showcase"

    assert_text "Showcase was successfully created"
    click_on "Back"
  end

  test "should update Showcase" do
    visit showcase_url(@showcase)
    click_on "Edit this showcase", match: :first

    fill_in "Key", with: @showcase.key
    fill_in "Name", with: @showcase.name
    fill_in "Location", with: @showcase.location_id
    fill_in "Year", with: @showcase.year
    click_on "Update Showcase"

    assert_text "Showcase was successfully updated"
    click_on "Back"
  end

  test "should destroy Showcase" do
    visit showcase_url(@showcase)
    click_on "Destroy this showcase", match: :first

    assert_text "Showcase was successfully destroyed"
  end
end
