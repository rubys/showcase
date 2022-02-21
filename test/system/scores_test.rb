require "application_system_test_case"

class ScoresTest < ApplicationSystemTestCase
  setup do
    @score = scores(:one)
  end

  test "should update score" do
    visit person_url(people(:Judy))
    click_on "Score heats"
    click_on "Solo Waltz"

    source = page.find('div[draggable=true]')
    target = page.find('div[data-score=G]')
    source.drag_to(target)

    visit by_level_scores_path
    # doesn't appear to work yet
  end
end
