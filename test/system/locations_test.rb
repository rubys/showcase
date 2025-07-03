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
    skip "Geocoding API calls cause flaky test failures"
    visit locations_url
    click_on "New studio"

    fill_in "Token", with: @location.key + '2'
    fill_in "Latitude", with: @location.latitude
    fill_in "Longitude", with: @location.longitude
    fill_in "Name", with: @location.name + '2'
    select @location.user.name1, from: "Owner/Contact"
    click_on "Create Studio"

    assert_text "Florida2 was successfully created"
    click_on "Back"
  end

  test "should update Location" do
    skip "Geocoding API calls cause flaky test failures"
    visit location_url(@location)
    click_on "Edit this location", match: :first

    fill_in "Token", with: @location.key
    fill_in "Latitude", with: @location.latitude
    fill_in "Longitude", with: @location.longitude
    fill_in "Name", with: @location.name
    select @location.user.name1, from: "Owner/Contact"
    click_on "Update Location"

    assert_text "Florida was successfully updated"
    click_on "Back"
  end

  test "should destroy Location" do
    visit location_url(@location)
    click_on "Destroy this location", match: :first

    assert_text "Florida was successfully destroyed"
  end
end
