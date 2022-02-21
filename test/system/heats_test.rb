require "application_system_test_case"

class HeatsTest < ApplicationSystemTestCase
  setup do
    @heat = heats(:one)
  end

  test "visiting the index" do
    visit heats_url
    assert_selector "h1", text: "Agenda"
  end

  test "should update Heat" do
    visit person_url(people(:Kathryn))
    page.find('td', text: 'Open').hover
    click_on "Edit"

    select "Full Gold", from: "heat_level"
    click_on "Update Heat"

    assert_text "Heat was successfully updated"
    click_on "Back"
  end

  test "should remove Heat" do
    visit person_url(people(:Kathryn))
    page.find('td', text: 'Closed').hover
    click_on "Edit"

    click_on "Remove this heat"
    page.accept_alert

    assert_text "Heat was successfully removed"
  end
end
