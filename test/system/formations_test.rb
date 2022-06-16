require "application_system_test_case"

class FormationsTest < ApplicationSystemTestCase
  test "should create formation" do
    visit person_url(people(:Kathryn))
    click_on "Add formation", match: :first

    select "Rumba", from: "Dance"
    click_on "Create Formation"

    assert_text "Formation was successfully created"
    click_on "Back"
  end

  test "should update Formation" do
    visit person_url(people(:Kathryn))

    within find('caption', text: 'Solos').sibling('tbody') do
      find('td', text: 'Full Silver').hover
      click_on "Edit"
    end

    fill_in "Song", with: "Por Una Cabeza"
    click_on "Update Formation"

    assert_text "Formation was successfully updated"
    click_on "Back"
  end

  test "should scratch Formation" do
    visit person_url(people(:Kathryn))

    within find('caption', text: 'Solos').sibling('tbody') do
      find('td', text: 'Full Silver').hover
      click_on "Edit"
    end

    click_on "Scratch this formation"

    assert_text "Formation was successfully scratched"
  end
end