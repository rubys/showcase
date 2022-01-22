require "application_system_test_case"

class PeopleTest < ApplicationSystemTestCase
  setup do
    @person = people(:one)
  end

  test "visiting the index" do
    visit people_url
    assert_selector "h1", text: "People"
  end

  test "should create person" do
    visit people_url
    click_on "New person"

    fill_in "Back", with: @person.back
    fill_in "Category", with: @person.category
    check "Friday dinner" if @person.friday_dinner
    fill_in "Level", with: @person.level
    fill_in "Name", with: @person.name
    fill_in "Role", with: @person.role
    check "Saturday dinner" if @person.saturday_dinner
    check "Saturday lunch" if @person.saturday_lunch
    fill_in "Studio", with: @person.studio_id
    fill_in "Type", with: @person.type
    click_on "Create Person"

    assert_text "Person was successfully created"
    click_on "Back"
  end

  test "should update Person" do
    visit person_url(@person)
    click_on "Edit this person", match: :first

    fill_in "Back", with: @person.back
    fill_in "Category", with: @person.category
    check "Friday dinner" if @person.friday_dinner
    fill_in "Level", with: @person.level
    fill_in "Name", with: @person.name
    fill_in "Role", with: @person.role
    check "Saturday dinner" if @person.saturday_dinner
    check "Saturday lunch" if @person.saturday_lunch
    fill_in "Studio", with: @person.studio_id
    fill_in "Type", with: @person.type
    click_on "Update Person"

    assert_text "Person was successfully updated"
    click_on "Back"
  end

  test "should destroy Person" do
    visit person_url(@person)
    click_on "Destroy this person", match: :first

    assert_text "Person was successfully destroyed"
  end
end
