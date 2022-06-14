require "test_helper"

class HeatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @heat = heats(:one)
    @primary = people(:Kathryn)
  end

  test "should get index" do
    get heats_url
    assert_response :success
  end

  test "should get master heat book" do
    get book_heats_url
    assert_response :success
  end

  test "should get judge heat book" do
    get book_heats_url(type: 'judge')
    assert_response :success
  end

  test "should get new" do
    get new_heat_url, params: { primary: @primary.id }
    assert_response :success
    get new_heat_url
    assert_response :success
  end

  test "should create heat" do
    assert_difference("Heat.count") do
      post heats_url, params: { heat: { primary: @primary.id, partner: people(:Arthur).id, age: @heat.entry.age_id, level: @heat.entry.level_id, category: @heat.category, dance_id: @heat.dance_id } }
    end

    assert_redirected_to heat_url(Heat.last)
  end

  test "should show heat" do
    get heat_url(@heat)
    assert_response :success
  end

  test "should get edit" do
    get edit_heat_url(@heat, primary: @primary.id)
    assert_response :success
    get edit_heat_url
    assert_response :success
  end

  test "should update heat" do
    patch heat_url(@heat), params: { heat: { primary: @primary.id, partner: people(:Arthur).id, age: @heat.entry.age_id, level: @heat.entry.level_id, category: @heat.category, dance_id: @heat.dance_id } }

    assert_redirected_to person_url(@primary)
    assert_equal flash[:notice], 'Heat was successfully updated.'
  end

  test "should destroy heat" do
    @heat = heats(:zero)
    assert_difference("Heat.count", -1) do
      delete heat_url(@heat)
    end

    assert_response 303
    assert_redirected_to heats_url
  end

  test "should scratch heat" do
    delete heat_url(@heat)
    @heat.reload
    assert_operator @heat.number, :<, 0

    assert_response 303
    assert_redirected_to heats_url
  end
end
