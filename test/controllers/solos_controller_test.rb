require "test_helper"

class SolosControllerTest < ActionDispatch::IntegrationTest
  setup do
    @solo = solos(:one)
    @primary = people(:Kathryn)
  end

  test "should get index" do
    get solos_url
    assert_response :success
  end

  test "should get new" do
    get new_solo_url(primary: @primary.id)
    assert_response :success
    get new_solo_url
    assert_response :success
  end

  test "should create solo" do
    assert_difference("Solo.count") do
      post solos_url, params: { solo: { 
        primary: @primary.id,
        partner: people(:Arthur).id,
        age: @solo.heat.entry.age_id,
        level: @solo.heat.entry.level_id,
        dance_id: @solo.heat.dance_id, 
        combo_dance_id: @solo.combo_dance_id, 
        heat_id: @solo.heat_id, 
        order: @solo.order
       } }
    end

    assert_redirected_to person_url(@primary)
    assert_equal flash[:notice], 'Solo was successfully created.'
  end

  test "should show solo" do
    get solo_url(@solo, primary: @primary.id)
    assert_response :success
  end

  test "should get edit" do
    get edit_solo_url(@solo, primary: @primary.id)
    assert_response :success
    get edit_solo_url
    assert_response :success
  end

  test "should update solo" do
    patch solo_url(@solo), params: { solo: { 
      primary: @primary.id,
      partner: people(:Arthur).id,
      age: @solo.heat.entry.age_id,
      level: @solo.heat.entry.level_id,
      dance_id: @solo.heat.dance_id, 
      combo_dance_id: @solo.combo_dance_id, 
      heat_id: @solo.heat_id, 
      order: @solo.order
     } }

    assert_redirected_to person_url(@primary)
    assert_equal flash[:notice], 'Solo was successfully updated.'
  end

  test "should reorder solos" do
    post drop_solos_url, as: :turbo_stream, params: {
      source: solos(:two).id,
      target: solos(:one).id
    }
      
    assert_response :success

    assert_equal 2, solos(:two).order
    solos(:two).reload
    assert_equal 1, solos(:two).order
  end

  test "should destroy solo" do
    assert_difference("Solo.count", -1) do
      delete solo_url(@solo, primary: @primary.id)
    end

    assert_response 303
    assert_redirected_to person_url(@primary)
    assert_equal flash[:notice], 'Solo was successfully removed.'
  end
end
