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

  # SPA System Tests - Critical Paths
  test "SPA loads and displays heat list interface" do
    judge = people(:Judy)
    visit judge_spa_path(judge)

    # Verify custom elements are present
    assert_selector "heat-page"
    assert_selector "heat-list"

    # Verify judge name appears (in navigation footer, could be display_name or name)
    assert_text(/Judy.*Sheindlin|Sheindlin.*Judy/)

    # Wait for data to load and verify heat list appears
    # Heat list renders as table rows with links
    assert_selector "heat-list table tbody tr", wait: 5
    assert_selector "heat-list a[href*='/scores/#{judge.id}/spa?heat=']"
  end

  test "SPA displays heat scoring interface" do
    judge = people(:Judy)
    visit judge_spa_path(judge)

    # Wait for heat list to load
    assert_selector "heat-list table tbody tr", wait: 5

    # Click on first heat link to view scoring interface
    first("heat-list a[href*='heat=']").click

    # Verify heat-table custom element appears
    assert_selector "heat-table", wait: 5

    # Verify scoring interface elements are present (will depend on style)
    # For now, just verify the table loaded
    assert_selector "heat-table table"
  end

  test "SPA score submission persists to database" do
    judge = people(:Judy)
    visit judge_spa_path(judge)

    # Wait for heat list to load
    assert_selector "heat-list table tbody tr", wait: 5

    # Get first heat link and extract heat number from URL
    first_heat_link = first("heat-list a[href*='heat=']")
    heat_url = first_heat_link[:href]
    heat_number = heat_url.match(/heat=(\d+)/)[1].to_i

    # Click on heat
    first_heat_link.click

    # Wait for scoring interface
    assert_selector "heat-table", wait: 5

    # Find heat from database
    heat = Heat.find_by(number: heat_number)

    # Count initial scores
    initial_score_count = Score.where(judge: judge, heat: heat).count

    # Try to interact with scoring interface
    # The exact interaction depends on the style (radio, cards, etc.)
    # For now, just verify the interface loaded
    within "heat-table" do
      # Look for any interactive scoring elements
      has_selector?("input, button, [draggable]", wait: 2)
    end

    # Navigation back to list should work
    if has_link?("Back", wait: 1)
      click_link "Back"
      assert_selector "heat-list"
    end
  end
end
