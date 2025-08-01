require "test_helper"

class ShowcasesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @showcase = showcases(:one)
  end

  test "should get index" do
    get showcases_url
    assert_response :success
  end

  test "should get new" do
    get new_showcase_url(location: @showcase.location.id)
    assert_response :success
  end

  test "should create showcase" do
    assert_difference("Showcase.count") do
      post showcases_url, params: { showcase: { key: @showcase.key+'2', name: @showcase.name+'2', location_id: @showcase.location_id, year: @showcase.year } }
    end

    assert_redirected_to events_location_path(@showcase.location)
    assert_equal 'MyString2 was successfully requested.', flash[:notice]
  end

  test "should show showcase" do
    get showcase_url(@showcase)
    assert_response :success
  end

  test "should get edit" do
    get edit_showcase_url(@showcase)
    assert_response :success
  end

  test "should update showcase" do
    patch showcase_url(@showcase), params: { showcase: { key: @showcase.key, name: @showcase.name, location_id: @showcase.location_id, year: @showcase.year } }
    assert_redirected_to events_location_path(@showcase.location)
    assert_equal 'MyString was successfully updated.', flash[:notice]
  end

  test "should destroy showcase" do
    assert_difference("Showcase.count", -1) do
      delete showcase_url(@showcase)
    end

    assert_response 303
    assert_redirected_to events_location_path(@showcase.location)
    assert_equal 'MyString was successfully destroyed.', flash[:notice]
  end

  test "should get new_request" do
    get studio_request_url(location_key: @showcase.location.key)
    assert_response :success
  end

  test "should handle edit when database doesn't exist" do
    # Create a showcase that won't have a corresponding database
    showcase = Showcase.create!(
      name: "Nonexistent DB Test",
      key: "nonexistent-test",
      year: 9999,
      location: @showcase.location
    )
    
    get edit_showcase_url(showcase)
    assert_response :success
    # Just verify the page loads without error when database doesn't exist
    assert_select "h2", text: "Statistics:"
  end
end
