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

  test "should get individual scores" do
    get scores_person_url(@person)
    assert_response :success
  end

  test "should create person" do
    assert_difference("Person.count") do
      post people_url, params: { person: { age_id: @person.age_id, back: 301, level_id: @person.level_id, name: 'Fred Astaire', role: @person.role, studio_id: @person.studio_id, type: @person.type, exclude_id: '' } }
    assert_equal flash[:notice], 'Fred Astaire was successfully added.'
    end

    assert_redirected_to person_url(Person.last)
  end

  test "should create judge" do
    assert_difference("Person.count") do
      post people_url, params: { person: { name: 'Joseph Wopner', type: 'Judge', studio_id: 0 } }
    assert_equal flash[:notice], 'Joseph Wopner was successfully added.'
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
    patch person_url(@person), params: { person: { age_id: @person.age_id, back: @person.back, level_id: @person.level_id, name: @person.name, role: @person.role, studio_id: @person.studio_id, type: @person.type, exclude_id: '' } }
    assert_redirected_to person_url(@person)
    assert_equal flash[:notice], 'Arthur Murray was successfully updated.'
  end

  test "should update person with table assignment" do
    table = tables(:one)
    patch person_url(@person), params: { person: { age_id: @person.age_id, back: @person.back, level_id: @person.level_id, name: @person.name, role: @person.role, studio_id: @person.studio_id, type: @person.type, table_id: table.id, exclude_id: '' } }
    assert_redirected_to person_url(@person)
    assert_equal flash[:notice], 'Arthur Murray was successfully updated.'
    @person.reload
    assert_equal table.id, @person.table_id
  end

  test "should show table options for Professional in edit" do
    get edit_person_url(@person)
    assert_response :success
    assert_match /Table \d+ -/, response.body
  end

  test "should show table options for Student in edit" do
    student = people(:Kathryn)
    get edit_person_url(student)
    assert_response :success
    assert_match /Table \d+ -/, response.body
  end

  test "should show table options for Guest in edit" do
    guest = people(:guest)
    get edit_person_url(guest)
    assert_response :success
    assert_match /Table \d+ -/, response.body
  end

  test "should not show table options for Judge in edit" do
    judge = people(:Judy)
    get edit_person_url(judge)
    assert_response :success
    assert_no_match /Table \d+ -/, response.body
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
