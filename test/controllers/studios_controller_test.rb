require "test_helper"

class StudiosControllerTest < ActionDispatch::IntegrationTest
  setup do
    @studio = studios(:one)
  end

  test "should get index" do
    get studios_url
    assert_response :success
  end

  test "should get new" do
    get new_studio_url
    assert_response :success
  end

  test "should create studio" do
    assert_difference("Studio.count") do
      post studios_url, params: { studio: { name: 'Mars' } }
    end

    assert_redirected_to studio_url(Studio.last)
    assert_equal flash[:notice], 'Mars was successfully created.'
  end

  test "should show studio" do
    get studio_url(@studio)
    assert_response :success
  end

  test "should get studio heat sheet" do
    get heats_studio_url(@studio)
    assert_response :success
  end

  test "should get studio scores" do
    get scores_studio_url(@studio)
    assert_response :success
  end

  test "should get edit" do
    get edit_studio_url(@studio)
    assert_response :success
  end

  test "should update studio" do
    patch studio_url(@studio), params: { studio: { name: @studio.name } }
    assert_redirected_to studio_url(@studio)
    assert_equal flash[:notice], 'One was successfully updated.'
  end

  test "shoudl pair studio" do
    three = studios(:three)

    patch studio_url(@studio), params: { studio: { pair: three.name } }
    assert_redirected_to studio_url(@studio)

    assert_equal [@studio], three.pairs
    assert_equal 2, @studio.pairs.length
    assert_includes @studio.pairs, three
  end

  test "shoudl unpair studio - left" do
    two = studios(:two)

    post unpair_studio_url(@studio), params: { pair: two.name }
    assert_redirected_to edit_studio_url(@studio)

    assert_empty two.pairs
    assert_empty @studio.pairs
  end

  test "shoudl unpair studio - right" do
    two = studios(:two)

    post unpair_studio_url(two), params: { pair: @studio.name }
    assert_redirected_to edit_studio_url(two)

    assert_empty two.pairs
    assert_empty @studio.pairs
  end

  test "should destroy studio" do
    assert_difference("Studio.count", -1) do
      delete studio_url(@studio)
    end

    assert_response 303
    assert_redirected_to studios_url
    assert_equal flash[:notice], 'One was successfully removed.'
  end
end
