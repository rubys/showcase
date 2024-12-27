require "application_system_test_case"

class ScoresTest < ApplicationSystemTestCase
  setup do
    @score = scores(:one)
  end

  test "should update score - solo" do
    visit person_url(people(:Judy))
    click_on "Score heats - cards"
    click_on "Solo Waltz"

    source = page.find('textarea[data-score-target=comments]')
    target = page.find('input[data-score-target=score]')
    source.drag_to(target)

    visit by_level_scores_path
    assert_selector "td", text: "6"
  end

  test "should update score - closed" do
    visit person_url(people(:Judy))
    click_on "Score heats - cards"
    click_on "Closed Waltz"

    source = page.find('div[draggable=true]')
    target = page.find('div[data-score=G]')
    source.drag_to(target)

    visit by_level_scores_path
    assert_selector "td", text: "6"
  end
end
