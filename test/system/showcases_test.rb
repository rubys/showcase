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

  test "site owner can request a showcase with auto-generated key" do
    location = locations(:one)
    
    visit studio_request_url(location_key: location.key)
    
    assert_selector "h1", text: "Request new showcase"
    
    # Verify year field is not present
    assert_no_selector "label", text: "Year"
    
    # Fill in the name field
    fill_in "Name", with: "Spring Gala"
    
    # The key should be auto-generated as a hidden field
    # Wait a moment for the stimulus controller to update
    sleep 0.2
    
    # Verify the hidden key field has been populated
    key_value = find("#showcase_key", visible: false).value
    assert_equal "spring-gala", key_value
    
    # Verify the form has the date-range controller with proper targets
    assert_selector "[data-controller='date-range']"
    assert_selector "[data-date-range-target='startDate']"
    assert_selector "[data-date-range-target='endDate']"
  end

  test "site owner must provide start date when requesting showcase" do
    location = locations(:one)
    visit studio_request_url(location_key: location.key)
    
    fill_in "Name", with: "Test Showcase"
    
    # Try to submit without start date
    click_on "Request Showcase"
    
    # Browser validation should prevent submission
    # Check that we're still on the same page
    assert_selector "h1", text: "Request new showcase"
  end

end
