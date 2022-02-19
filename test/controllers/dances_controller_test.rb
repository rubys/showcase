require "test_helper"

class DancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @dance = dances(:waltz)
  end

  test "should get index" do
    get dances_url
    assert_response :success
  end

  test "should get new" do
    get new_dance_url
    assert_response :success
  end

  test "should create dance" do
    assert_difference("Dance.count") do
      post dances_url, params: { dance: {
        open_category: @dance.open_category,
        closed_category: @dance.closed_category,
        name: @dance.name
       } }
    end

    assert_redirected_to dance_url(Dance.last)
  end

  test "should show dance" do
    get dance_url(@dance)
    assert_response :success
  end

  test "should get edit" do
    get edit_dance_url(@dance)
    assert_response :success
  end

  test "should update dance" do
    patch dance_url(@dance), params: { dance: {
      open_category: @dance.open_category,
      closed_category: @dance.closed_category,
      name: @dance.name
    } }
    assert_redirected_to dance_url(@dance)
  end

  test "should destroy dance" do
    assert_difference("Dance.count", -1) do
      delete dance_url(@dance)
    end

    assert_redirected_to dances_url
  end
end
