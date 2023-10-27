require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "should get index" do
    get users_url
    assert_response :success
  end

  test "should get new" do
    get new_user_url
    assert_response :success
  end

  test "should create user" do
    assert_difference("User.count") do
      sites =  @user.sites.split(',').map {|name| [name, 1]}.to_h
      post users_url, params: { user: { email: @user.email + '2', link: @user.link, name1: @user.name1, name2: @user.name2, password: @user.password, sites: sites, token: @user.token, userid: @user.userid + '2'} }
    end

    assert_redirected_to users_url
  end

  test "should show user" do
    get user_url(@user)
    assert_response :success
  end

  test "should get edit" do
    get edit_user_url(@user)
    assert_response :success
  end

  test "should update user" do
    sites =  @user.sites.split(',').map {|name| [name, 1]}.to_h
    patch user_url(@user), params: { user: { email: @user.email + '2', link: @user.link, name1: @user.name1, name2: @user.name2, password: @user.password, password_confirmation: @user.password, sites: sites, token: @user.token, userid: @user.userid + '2' } }
    assert_redirected_to users_url
  end

  test "should destroy user" do
    assert_difference("User.count", -1) do
      delete user_url(@user)
    end

    assert_response 303
    assert_redirected_to users_url
    assert_equal flash[:notice], 'joe was successfully removed.'
  end
end
