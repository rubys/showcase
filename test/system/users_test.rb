require "application_system_test_case"

class UsersTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
  end

  test "visiting the index" do
    visit users_url
    assert_selector "h1", text: "Users"
  end

  test "should create user" do
    visit users_url
    click_on "New user"

    fill_in "Email", with: @user.email + '2'
    fill_in "Link", with: @user.link
    fill_in "Name1", with: @user.name1
    fill_in "Name2", with: @user.name2
    fill_in "Password", with: @user.password
    fill_in "Password confirmation", with: @user.password
    fill_in "Sites", with: @user.sites
    fill_in "Token", with: @user.token
    fill_in "Userid", with: @user.userid + '2'
    click_on "Create User"

    assert_text "MyString12 was successfully created"
    click_on "Back"
  end

  test "should update User" do
    visit user_url(@user)
    click_on "Edit this user", match: :first

    fill_in "Email", with: @user.email
    fill_in "Link", with: @user.link
    fill_in "Name1", with: @user.name1
    fill_in "Name2", with: @user.name2
    fill_in "Password", with: @user.password
    fill_in "Password confirmation", with: @user.password
    fill_in "Sites", with: @user.sites
    fill_in "Token", with: @user.token
    fill_in "Userid", with: @user.userid 
    click_on "Update User"

    assert_text "MyString1 was successfully updated"
    click_on "Back"
  end

  test "should destroy User" do
    visit user_url(@user)
    click_on "Destroy this user", match: :first

    assert_text "MyString1 was successfully removed"
  end
end
