require "application_system_test_case"

class ScoresTest < ApplicationSystemTestCase
  setup do
    @score = scores(:one)
  end

  test "should update score" do
    visit person_url(people(:Judy))
    click_on "Score heats"
    click_on "Solo Waltz"

    # this doesn't work
    source = page.find('div[draggable=true]')
    target = page.find('div[data-score=G]')
    source.drag_to(target)

    if false
    # this also doesn't work
    page.driver.browser.action.drag_and_drop(source.native, target.native).perform

    # nor does this
    page.driver.browser.action.
      click_and_hold(source.native).
      move_to(target.native).
      release.
      click(target.native).
      perform
    end

    visit by_level_scores_path

  end
end
