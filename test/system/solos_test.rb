require "application_system_test_case"

class SolosTest < ApplicationSystemTestCase
  setup do
    @solo = solos(:one)
  end

  test "visiting the index" do
    visit solos_url
    assert_selector "h1", text: "Solos"
    assert_selector "td", text: "Closed American Smooth"
  end

  test "should create solo" do
    visit person_url(people(:Kathryn))
    click_on "Add solo", match: :first

    select "Rumba", from: "Dance"
    click_on "Create Solo"

    assert_text "Solo was successfully created"
    click_on "Back"
  end

  test "should update Solo" do
    visit person_url(people(:Kathryn))

    within find('caption', text: 'Solos').sibling('tbody') do
      find('td', text: 'Assoc. Silver').hover
      click_on "Edit"
    end

    fill_in "Song", with: "Por Una Cabeza"
    click_on "Update Solo"

    assert_text "Solo was successfully updated"
    click_on "Back"
  end

  test "should destroy Solo" do
    visit person_url(people(:Kathryn))

    within find('caption', text: 'Solos').sibling('tbody') do
      find('td', text: 'Assoc. Silver').hover
      click_on "Edit"
    end

    click_on "Remove this solo"
    page.accept_alert

    assert_text "Solo was successfully removed"
  end
end
