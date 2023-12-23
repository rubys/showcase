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

    assert_redirected_to edit_location_url(@showcase.location)
    assert_equal flash[:notice], 'MyString2 was successfully created.'
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
    assert_redirected_to edit_location_url(@showcase.location)
    assert_equal flash[:notice], 'MyString was successfully updated.'
  end

  test "should destroy showcase" do
    assert_difference("Showcase.count", -1) do
      delete showcase_url(@showcase)
    end

    assert_response 303
    assert_redirected_to edit_location_url(@showcase.location)
    assert_equal flash[:notice], 'MyString was successfully destroyed.'
  end
end
