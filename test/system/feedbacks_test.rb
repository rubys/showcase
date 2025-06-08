require "application_system_test_case"

class FeedbacksTest < ApplicationSystemTestCase
  setup do
    @feedback = feedbacks(:one)
  end

  test "visiting the index" do
    visit feedbacks_url
    assert_selector "h1", text: "Feedback Buttons"
  end

  test "should create feedback" do
    visit feedbacks_url
    find_all("input[value='']").first.set("Poise")
    find_all("input").first.click

    assert_selector "input[value='P']"
    assert_selector "span", text: "Poise"
    click_on "Back to settings"
  end

  test "should update Feedback" do
    visit feedback_url(@feedback)
    click_on "Edit this feedback", match: :first

    fill_in "Abbr", with: @feedback.abbr
    fill_in "Order", with: @feedback.order
    fill_in "Value", with: @feedback.value
    click_on "Update Feedback"

    assert_text "Feedback was successfully updated"
    click_on "Back"
  end

  test "should destroy Feedback" do
    visit feedback_url(@feedback)
    click_on "Destroy this feedback", match: :first

    assert_text "Feedback was successfully destroyed"
  end
end
