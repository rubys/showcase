require "application_system_test_case"

class SolosTest < ApplicationSystemTestCase
  setup do
    @solo = solos(:one)
  end

  test "visiting the index" do
    visit solos_url
    assert_selector "h1", text: "Solos"
  end

  test "should create solo" do
    visit solos_url
    click_on "New solo"

    fill_in "Combo dance", with: @solo.combo_dance_id
    fill_in "Heat", with: @solo.heat_id
    fill_in "Order", with: @solo.order
    click_on "Create Solo"

    assert_text "Solo was successfully created"
    click_on "Back"
  end

  test "should update Solo" do
    visit solo_url(@solo)
    click_on "Edit this solo", match: :first

    fill_in "Combo dance", with: @solo.combo_dance_id
    fill_in "Heat", with: @solo.heat_id
    fill_in "Order", with: @solo.order
    click_on "Update Solo"

    assert_text "Solo was successfully updated"
    click_on "Back"
  end

  test "should destroy Solo" do
    visit solo_url(@solo)
    click_on "Destroy this solo", match: :first

    assert_text "Solo was successfully destroyed"
  end
end
