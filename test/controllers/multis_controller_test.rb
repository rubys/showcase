require "test_helper"

class MultisControllerTest < ActionDispatch::IntegrationTest
  setup do
    @dance = dances(:aa_smooth)
  end

  test "should get index" do
    get multis_url
    assert_response :success
  end

  test "should get new" do
    get new_multi_url
    assert_response :success
  end

  test "should create multi" do
    assert_difference("Multi.count", 2) do
      post multis_url, params: 
      {dance: {"name"=>"Smooth All Around", "heat_length"=>"2", "multi"=>{"Waltz"=>"1", "Tango"=>"1"}}}
    end

    assert_redirected_to dances_url
  end

  test "should get edit" do
    get edit_multi_url(@dance)
    assert_response :success
  end

  test "should update multi" do
    patch multi_url(@dance), params: {dance: {"name"=>"Smooth All Around", "heat_length"=>"2", "multi"=>{"Waltz"=>"1", "Tango"=>"1"}}}
    assert_redirected_to dances_url
  end

  test "should destroy multi" do
    assert_difference("Multi.count", -2) do
      delete multi_url(@dance)
    end

    assert_response 303
    assert_redirected_to dances_url
  end
end
