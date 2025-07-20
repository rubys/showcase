require "application_system_test_case"

class EntriesTest < ApplicationSystemTestCase
  setup do
    @entry = entries(:one)
  end

  test "should create entry" do
    visit person_url(people(:Kathryn))
    click_on "Add heats", match: :first

    assert has_no_button?('Create Entry')

    select "Arthur Murray", from: "entry[partner]"

    assert has_button?('Create Entry')

    within page.find('h2', text: 'CLOSED CATEGORY').sibling('div') do
      check "Tango"
      check "Rumba"
    end

    click_on "Create Entry"

    assert_text "2 heats successfully created"
    click_on "Back"
  end

  test "should update Entry - addition" do
    visit person_url(people(:Kathryn))

    within find('caption', text: 'Entries').sibling('tbody') do
      row = find('td', text: 'Assoc. Silver').ancestor('tr')
      row.hover
      sleep 0.3  # Allow hover effect to take effect
      within row do
        find('button', text: 'Edit', visible: true).click
      end
    end

    within page.find('h2', text: 'CLOSED CATEGORY').sibling('div') do
      check "Tango"
      check "Rumba"
    end

    click_on "Update Entry"

    assert_text "2 heats added"
    click_on "Back"
  end

  test "should update Entry - modification" do
    visit person_url(people(:Kathryn))

    within find('caption', text: 'Entries').sibling('tbody') do
      row = find('td', text: 'Full Silver').ancestor('tr')
      row.hover
      sleep 0.3  # Allow hover effect to take effect
      within row do
        find('button', text: 'Edit', visible: true).click
      end
    end

    within page.find('h2', text: 'CLOSED CATEGORY').sibling('div') do
      check "Tango"
    end

    within page.find('h2', text: 'OPEN CATEGORY').sibling('div') do
      uncheck "Tango"
    end

    click_on "Update Entry"

    assert_text "2 heats changed"
    click_on "Back"
  end

  test "should update Entry - deletion" do
    visit person_url(people(:Kathryn))

    within find('caption', text: 'Entries').sibling('tbody') do
      row = find('td', text: 'Full Silver').ancestor('tr')
      row.hover
      sleep 0.3  # Allow hover effect to take effect
      within row do
        find('button', text: 'Edit', visible: true).click
      end
    end

    within page.find('h2', text: 'OPEN CATEGORY').sibling('div') do
      uncheck "Tango"
    end

    click_on "Update Entry"

    assert_text "1 heat changed"
    click_on "Back"
  end

  test "should scratch Entry" do
    visit person_url(people(:Kathryn))

    within find('caption', text: 'Entries').sibling('tbody') do
      row = find('td', text: 'Full Silver').ancestor('tr')
      row.hover
      sleep 0.3  # Allow hover effect to take effect
      within row do
        find('button', text: 'Edit', visible: true).click
      end
    end

    click_on "Scratch this entry", match: :first

    assert_text "3 heats scratched"
  end
end
