require "test_helper"

class HeatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @heat = heats(:one)
  end

  test "should get index" do
    get heats_url
    assert_response :success
  end

  test "should get new" do
    get new_heat_url
    assert_response :success
  end

  test "should create heat" do
    assert_difference("Heat.count") do
      post heats_url, params: { heat: { entry_id: @heat.entry_id, number: @heat.number } }
    end

    assert_redirected_to heat_url(Heat.last)
  end

  test "should show heat" do
    get heat_url(@heat)
    assert_response :success
  end

  test "should get edit" do
    get edit_heat_url(@heat)
    assert_response :success
  end

  test "should update heat" do
    patch heat_url(@heat), params: { heat: { entry_id: @heat.entry_id, number: @heat.number } }
    assert_redirected_to heat_url(@heat)
  end

  test "should destroy heat" do
    assert_difference("Heat.count", -1) do
      delete heat_url(@heat)
    end

    assert_redirected_to heats_url
  end
end
