require "application_system_test_case"

class PeopleTest < ApplicationSystemTestCase
  setup do
    @person = people(:Kathryn)
  end

  test "visiting the index" do
    visit people_url
    assert_selector "h1", text: "Event Participants"
  end

  test "should create person" do
    visit studio_url(studios(:one))
    click_on "Add Person"

    fill_in "Name", with: 'Doe, Jane'
    select 'Guest', from: 'Type'

    assert_no_selector "#person_level_id"
    assert_no_selector "#person_age_id"
    assert_no_selector "#person_role"
    assert_no_selector "#person_back"

    select 'Professional', from: 'Type'
    assert_selector "#person_role"
    select 'Follower', from: 'Role'
    assert_no_selector "#person_level_id"
    assert_no_selector "#person_age_id"
    assert_no_selector "#person_back"

    select 'Student', from: 'Type'
    assert_selector "#person_role"
    select 'Follower', from: 'Role'
    assert_selector "#person_level_id"
    assert_selector "#person_age_id"
    assert_no_selector "#person_back"

    select 'Leader', from: 'Role'
    assert_selector "#person_back"
    fill_in "Back", with: '123'
    click_on "Create Person"

    assert_text "Jane Doe was successfully added"
    click_on "Back"
  end

  test "should create judge" do
    visit  settings_event_index_url(tab: 'Staff')
    click_on "Add person"

    select 'Judge', from: 'Type'

    # intermittent timing problem if this is set later
    fill_in "Name", with: 'Wopner, Joseph'

    assert_no_selector "#person_level_id"
    assert_no_selector "#person_age_id"
    assert_no_selector "#person_role"
    assert_no_selector "#person_back"

    click_on "Create Person"

    assert_text "Joseph Wopner was successfully added"
    assert_equal 'Event Staff', page.all('h1').first.text
  end

  test "should update Person" do
    visit person_url(@person)
    click_on "Edit this person", match: :first

    select 'Both', from: 'Role'
    click_on "Update Person"

    assert_text "Kathryn Murray was successfully updated"
    click_on "Back"
  end

  test "should assign table to Student" do
    visit person_url(@person)
    click_on "Edit this person", match: :first

    # Table dropdown should be visible for Student
    assert_selector "#person_table_id"
    select 'Table 1 -', from: 'Table'
    click_on "Update Person"

    assert_text "Kathryn Murray was successfully updated"
    click_on "Back"
  end

  test "should assign table to Professional" do
    professional = people(:Arthur)
    visit person_url(professional)
    click_on "Edit this person", match: :first

    # Table dropdown should be visible for Professional
    assert_selector "#person_table_id"
    select 'Table 2 -', from: 'Table'
    click_on "Update Person"

    assert_text "Arthur Murray was successfully updated"
    click_on "Back"
  end

  test "should assign table to Guest" do
    guest = people(:guest)
    visit person_url(guest)
    click_on "Edit this person", match: :first

    # Table dropdown should be visible for Guest
    assert_selector "#person_table_id"
    select 'Table 1 -', from: 'Table'
    click_on "Update Person"

    assert_text "Guest was successfully updated"
    click_on "Back"
  end

  test "should not show table options for Judge" do
    judge = people(:Judy)
    visit person_url(judge)
    click_on "Edit this person", match: :first

    # Table dropdown should not be visible for Judge
    assert_no_selector "#person_table_id"
  end

  test "should destroy Person" do
    visit person_url(@person)
    click_on "Edit this person", match: :first
    click_on "Remove this person", match: :first
    page.accept_alert

    assert_text "Kathryn Murray was successfully removed"
  end
end
