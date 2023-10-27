require "application_system_test_case"

class LocationsTest < ApplicationSystemTestCase
  setup do
    @location = locations(:one)
  end

  test "visiting the index" do
    visit locations_url
    assert_selector "h1", text: "Studios"
  end

  test "should create location" do
    visit locations_url
    click_on "New studio"

    fill_in "Key", with: @location.key
    fill_in "Latitude", with: @location.latitude
    fill_in "Longitude", with: @location.longitude
    fill_in "Name", with: @location.name
    select @location.user.name1, from: "Owner/Contact"
    click_on "Create Location"

    assert_text "Location was successfully created"
    click_on "Back"
  end

  test "should update Location" do
    visit location_url(@location)
    click_on "Edit this location", match: :first

    fill_in "Key", with: @location.key
    fill_in "Latitude", with: @location.latitude
    fill_in "Longitude", with: @location.longitude
    fill_in "Name", with: @location.name
    select @location.user.name1, from: "Owner/Contact"
    click_on "Update Location"

    assert_text "Location was successfully updated"
    click_on "Back"
  end

  test "should destroy Location" do
    visit location_url(@location)
    click_on "Destroy this location", match: :first

    assert_text "Location was successfully destroyed"
  end
end
