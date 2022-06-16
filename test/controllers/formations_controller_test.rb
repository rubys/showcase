require "test_helper"

class FormationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @solo = solos(:two)
    @primary = people(:Kathryn)
  end

  test "should get new" do
    get new_formation_url(primary: @primary.id)
    assert_response :success
    get new_formation_url
    assert_response :success
  end

  test "should create formation" do
    assert_difference("Formation.count") do
      post solos_url, params: { solo: { 
        primary: @primary.id,
        partner: people(:Arthur).id,
        formation: {'1' => people(:instructor1).id},
        age: @solo.heat.entry.age_id,
        level: @solo.heat.entry.level_id,
        dance_id: @solo.heat.dance_id, 
        combo_dance_id: '', 
        heat_id: @solo.heat_id, 
        order: @solo.order
       } }
    end

    assert_redirected_to person_url(@primary)
    assert_equal flash[:notice], 'Formation was successfully created.'
  end

  test "should get edit" do
    get edit_formation_url(@solo, primary: @primary.id)
    assert_response :success
    get edit_formation_url
    assert_response :success
  end

  test "should update solo" do
    patch solo_url(@solo), params: { solo: { 
      primary: @primary.id,
      partner: people(:Arthur).id,
      formation: {'1' => people(:instructor2).id},
      age: @solo.heat.entry.age_id,
      level: @solo.heat.entry.level_id,
      dance_id: @solo.heat.dance_id, 
      combo_dance_id: '', 
      heat_id: @solo.heat_id, 
      order: @solo.order
     } }

    assert_redirected_to person_url(@primary)
    assert_equal flash[:notice], 'Formation was successfully updated.'
  end

  test "should scratch formation" do
    delete solo_url(@solo, primary: @primary.id)
    @solo.heat.reload
    assert_operator @solo.heat.number, :<, 0

    assert_response 303
    assert_redirected_to person_url(@primary)
    assert_equal flash[:notice], 'Formation was successfully scratched.'
  end
end