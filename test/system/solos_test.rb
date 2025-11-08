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

  test "displays visual separator for split categories" do
    # Create a category with a split point
    category_with_split = Category.create!(
      name: "Test Split Solos",
      order: 200,
      split: "2"
    )

    # Create a dance associated with this category
    dance = Dance.create!(
      name: "Test Dance",
      order: 200,
      solo_category: category_with_split
    )

    level = levels(:one)
    age = ages(:one)

    # Create 4 solos in this category
    4.times do |i|
      entry = Entry.create!(
        lead: people(:Kathryn),
        follow: people(:Arthur),
        age: age,
        level: level
      )
      heat = Heat.create!(
        number: 300 + i,
        entry: entry,
        category: "Solo",
        dance: dance
      )
      Solo.create!(heat: heat, order: 3000 + i)
    end

    visit solos_url

    # Check that the category is displayed
    assert_text "Test Split Solos"

    # Check for the presence of a separator row (with gradient background)
    # The separator should have colspan="7" and specific styling
    assert_selector 'tr.separator-row td[colspan="7"]', count: 1
  end
end
