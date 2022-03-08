require "test_helper"

class PeopleControllerTest < ActionDispatch::IntegrationTest
  setup do
    @person = people(:Arthur)
  end

  test "should get index" do
    get people_url
    assert_response :success
  end

  test "should get new" do
    get new_person_url
    assert_response :success
  end

  test "should get heat sheets" do
    get heats_people_url
    assert_response :success
  end

  test "should get individual heat sheet" do
    get heats_person_url(@person)
    assert_response :success
  end

  test "should get students scores" do
    get scores_people_url
    assert_response :success
  end

  test "should create person" do
    assert_difference("Person.count") do
      post people_url, params: { person: { age_id: @person.age_id, back: 301, level_id: @person.level_id, name: 'Fred Astaire', role: @person.role, studio_id: @person.studio_id, type: @person.type } }
    assert_equal flash[:notice], 'Fred Astaire was successfully added.'
    end

    assert_redirected_to person_url(Person.last)
  end

  test "should show person" do
    get person_url(@person)
    assert_response :success
  end

  test "should get edit" do
    get edit_person_url(@person)
    assert_response :success
  end

  test "should update person" do
    patch person_url(@person), params: { person: { age_id: @person.age_id, back: @person.back, level_id: @person.level_id, name: @person.name, role: @person.role, studio_id: @person.studio_id, type: @person.type } }
    assert_redirected_to person_url(@person)
    assert_equal flash[:notice], 'Arthur Murray was successfully updated.'
  end

  test "should destroy person" do
    assert_difference("Person.count", -1) do
      delete person_url(@person)
    end

    assert_response 303
    assert_redirected_to studio_url(@person.studio)
    assert_equal flash[:notice], 'Arthur Murray was successfully removed.'
  end
end
