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

  test "should sync semi_finals to split dances on update" do
    # Create main dance with semi_finals
    main_dance = Dance.create!(
      name: "Latin 2 Dance Test",
      order: 400,
      multi_category: categories(:five),
      heat_length: 2,
      semi_finals: true
    )

    # Create split dance with different semi_finals
    split_dance = Dance.create!(
      name: "Latin 2 Dance Test",
      order: -1,
      multi_category: categories(:five),
      heat_length: 2,
      semi_finals: false
    )

    # Update main dance
    patch multi_url(main_dance), params: {
      dance: {
        "name" => "Latin 2 Dance Test",
        "heat_length" => "2",
        "semi_finals" => "1",
        "multi" => {}
      }
    }

    # Verify split dance was updated
    split_dance.reload
    assert split_dance.semi_finals, "Split dance should have semi_finals synced"
  end

  test "should toggle semi_finals on split dances" do
    # Create main dance with semi_finals true
    main_dance = Dance.create!(
      name: "Toggle Test",
      order: 401,
      multi_category: categories(:five),
      heat_length: 2,
      semi_finals: true
    )

    # Create split dance
    split_dance = Dance.create!(
      name: "Toggle Test",
      order: -1,
      multi_category: categories(:five),
      heat_length: 2,
      semi_finals: true
    )

    # Turn off semi_finals
    patch multi_url(main_dance), params: {
      dance: {
        "name" => "Toggle Test",
        "heat_length" => "2",
        "semi_finals" => "0",
        "multi" => {}
      }
    }

    # Verify split dance was updated
    split_dance.reload
    assert_not split_dance.semi_finals, "Split dance should have semi_finals disabled"
  end

  test "should not affect other dances with different names when syncing semi_finals" do
    # Create main dance
    main_dance = Dance.create!(
      name: "Sync Target",
      order: 402,
      multi_category: categories(:five),
      heat_length: 2,
      semi_finals: true
    )

    # Create split dance with same name
    split_dance = Dance.create!(
      name: "Sync Target",
      order: -1,
      multi_category: categories(:five),
      heat_length: 2,
      semi_finals: false
    )

    # Create unrelated dance with negative order
    unrelated_dance = Dance.create!(
      name: "Different Dance",
      order: -2,
      multi_category: categories(:five),
      heat_length: 2,
      semi_finals: false
    )

    # Update main dance
    patch multi_url(main_dance), params: {
      dance: {
        "name" => "Sync Target",
        "heat_length" => "2",
        "semi_finals" => "1",
        "multi" => {}
      }
    }

    # Verify split dance was updated
    split_dance.reload
    assert split_dance.semi_finals

    # Verify unrelated dance was not affected
    unrelated_dance.reload
    assert_not unrelated_dance.semi_finals, "Unrelated dance should not be affected"
  end
end
