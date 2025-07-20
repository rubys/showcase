require "application_system_test_case"

class SolosTest < ApplicationSystemTestCase
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
      row = find('td', text: 'Assoc. Silver').ancestor('tr')
      row.hover
      sleep 0.3  # Allow hover effect to take effect
      within row do
        find('button', text: 'Edit', visible: true).click
      end
    end

    fill_in "Song", with: "Por Una Cabeza"
    click_on "Update Solo"

    assert_text "Solo was successfully updated"
    click_on "Back"
  end

  test "should scratch Solo" do
    visit person_url(people(:Kathryn))

    within find('caption', text: 'Solos').sibling('tbody') do
      row = find('td', text: 'Assoc. Silver').ancestor('tr')
      row.hover
      sleep 0.3  # Allow hover effect to take effect
      within row do
        find('button', text: 'Edit', visible: true).click
      end
    end

    click_on "Scratch this solo"

    assert_text "Solo was successfully scratched"
  end
end
