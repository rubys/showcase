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

    assert_redirected_to controller: 'dances', action: 'index'
  end

  test "should show dance" do
    get dance_url(@dance)
    assert_response :success
  end

  test "should get edit" do
    get edit_dance_url(@dance)
    assert_response :success
    assert_select 'a[data-turbo-method=delete]', 'Remove this dance'
  end

  test "should update dance" do
    patch dance_url(@dance), params: { dance: {
      open_category: @dance.open_category,
      closed_category: @dance.closed_category,
      name: @dance.name
    } }

    assert_redirected_to dances_url
    assert_equal flash[:notice], 'Waltz was successfully updated.'
  end

  test "should reorder dances" do
    post drop_dances_url, as: :turbo_stream, params: {
      source: dances(:tango).id,
      target: dances(:waltz).id
    }
      
    assert_response :success

    assert_select 'tr td:first-child a' do |links|
      assert_equal %w(Tango Waltz), links.map(&:text)
    end

    assert_equal 2, dances(:tango).order
    dances(:tango).reload
    assert_equal 1, dances(:tango).order
  end

  test "should destroy dance" do
    assert_difference("Dance.count", -1) do
      delete dance_url(@dance)
    end

    assert_response 303
    assert_redirected_to dances_url
    assert_equal flash[:notice], 'Waltz was successfully removed.'
  end
end
