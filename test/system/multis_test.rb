require "application_system_test_case"

class MultisTest < ApplicationSystemTestCase
  setup do
    @dance = dances(:aa_smooth)
  end

  test "visiting the index" do
    visit multis_url
    assert_selector "h1", text: "Multis"
  end

  test "should create multi" do
    visit dances_url
    click_on "New multi-dance"

    fill_in "Name", with: "All Around Rhythm"
    fill_in "Number of heats", with: 2
    check "Rumba"
    check "Cha Cha"
    click_on "Create Dance"

    assert_text "All Around Rhythm was successfully created"
    click_on "Back"
  end

  test "should update Multi" do
    visit edit_multi_path(@dance.id)

    fill_in "Name", with: "All Around"
    fill_in "Number of heats", with: 4
    check "Rumba"
    check "Cha Cha"
    click_on "Update Dance"

    assert_text "All Around was successfully updated"
    click_on "Back"
  end

  test "should destroy Multi" do
    visit edit_multi_path(@dance.id)
    click_on "Remove this multi", match: :first
    page.accept_alert

    assert_text "All Around Smooth was successfully removed"
  end
end
