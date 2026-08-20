require "test_helper"

# Covers events that score open and closed heats differently -- in particular an
# event placing open heats 1/2/3/F while scoring closed heats 1-5 with feedback.
# The two styles share an alphabet, so every report has to know which category a
# score came from before it can bucket it.
class MixedScoringTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:one)
    @event.update!(open_scoring: '1', closed_scoring: '&', heat_range_cat: 0,
      strict_scoring: false, judge_comments: false)
    Event.current = @event

    @judge = people(:Judy)
    @closed_heat = heats(:one)   # entry one, Arthur (pro) and Kathryn (student)
    @open_heat = heats(:two)     # entry two, same couple

    assert_equal 'Closed', @closed_heat.category
    assert_equal 'Open', @open_heat.category

    Score.delete_all
    # A top closed score and a first place, both of which are written "5" / "1".
    Score.create!(judge: @judge, heat: @closed_heat, value: '5')
    Score.create!(judge: @judge, heat: @open_heat, value: '1')
  end

  # ===== SETTINGS =====

  test "judging settings offer number and feedback for closed heats" do
    get settings_event_index_path(tab: 'Judging')

    assert_response :success
    assert_select "input[name='event[closed_scoring]'][value='&']"
  end

  test "closed scoring of number and feedback can be saved" do
    @event.update!(closed_scoring: 'G')

    patch event_path(@event), params: { event: { closed_scoring: '&' }, tab: 'Judging' }

    assert_equal '&', @event.reload.closed_scoring
  end

  # ===== JUDGE SCORING INTERFACE =====

  test "closed heats get the 1-5 grid and feedback buttons" do
    get judge_heat_path(@judge, @closed_heat.number)

    assert_response :success
    assert_select 'div.value button.open-fb', 5
    assert_select 'div.good button.open-fb'
    assert_select 'div.bad button.open-fb'
  end

  test "open heats keep their placement radio buttons" do
    get judge_heat_path(@judge, @open_heat.number)

    assert_response :success
    assert_select 'input[type=radio]'
    assert_select 'div.value button.open-fb', 0
  end

  test "the heat json tells the offline interface each heat's own style" do
    get judge_heats_data_path(@judge)

    assert_response :success
    heats = JSON.parse(response.body)['heats']
    styles = heats.map { |heat| [heat['id'], heat['scoring_type']] }.to_h

    assert_equal '&', styles[@closed_heat.id]
    assert_equal '1', styles[@open_heat.id]
  end

  # ===== STANDINGS =====

  test "a closed 5 and an open 1 are counted in their own columns" do
    get details_by_level_scores_path

    assert_response :success

    # Closed columns run 5 down to 1, then the open placements 1/2/3/F.
    assert_equal %w(5 4 3 2 1 1 2 3 F), css_select('th.row-head').map(&:text).map(&:strip) - %w(Points Name)

    row = css_select('tbody tr, table tr').find { |tr| tr.text.include? 'Kathryn' }
    assert row, 'expected a row for the scored student'

    cells = row.css('td.row').map { |td| td.text.strip }
    # Five closed columns then four open ones: a single count in the top of each.
    assert_equal ['1', '', '', '', '', '1', '', '', ''], cells
  end

  test "the two scores are worth five points each" do
    get details_by_level_scores_path

    assert_response :success
    row = css_select('table tr').find { |tr| tr.text.include? 'Kathryn' }
    assert_equal '10', row.css('td.row-main').first.text.strip
  end

  test "by studio labels the two column groups and counts them apart" do
    get by_studio_scores_path

    assert_response :success

    groups = css_select('thead tr:first-child th').map { |th| th.text.strip }.reject(&:empty?)
    assert_equal %w(Closed Open), groups.first(2)

    headers = css_select('thead th.row-head').map { |th| th.text.strip }
    assert_equal %w(Points Name 5 4 3 2 1 1 2 3 F), headers.first(11)
  end

  test "by studio, by age and by level all render" do
    [by_level_scores_path, by_age_scores_path, by_studio_scores_path,
     details_by_level_scores_path, details_by_age_scores_path].each do |path|
      get path
      assert_response :success, "expected #{path} to render"
    end
  end

  test "the instructor summary shows feedback and points side by side" do
    get instructor_scores_path

    assert_response :success
    assert_select 'h2', text: 'Feedback'
    assert_select 'h2', text: 'Points'
  end

  test "the instructor summary shows points alone when nothing collects feedback" do
    @event.update!(open_scoring: '1', closed_scoring: 'G')

    get instructor_scores_path

    assert_response :success
    assert_select 'h2', text: 'Feedback', count: 0
    assert_select 'th.row-head', text: 'Points'
  end

  test "the instructor summary shows feedback alone when nothing earns points" do
    @event.update!(open_scoring: '+', closed_scoring: '=')

    get instructor_scores_path

    assert_response :success
    assert_select 'h2', text: 'Points', count: 0
  end

  # ===== PRINTED HEAT BOOK =====

  test "the judge's heat book prints a 1-5 grid on closed heats" do
    get book_heats_path(type: 'judge', judge: @judge.id)

    assert_response :success
    assert_select 'div.value button.open-fb'
    assert_select 'div.good button.open-fb'
  end

  test "the judge's heat book prints no grid when closed heats are placed" do
    @event.update!(closed_scoring: 'G')

    get book_heats_path(type: 'judge', judge: @judge.id)

    assert_response :success
    assert_select 'div.value button.open-fb', 0
  end

  # ===== STUDENT SCORE SHEETS =====

  test "student score sheets carry feedback for closed heats" do
    Score.find_by(heat: @closed_heat).update!(good: 'F T', bad: 'P')

    get scores_people_path

    assert_response :success
    assert_select 'body', text: /Great Job With/
  end

  test "a person's score tally separates closed scores from open placements" do
    get person_path(people(:Kathryn))

    assert_response :success

    headers = css_select('table th.row-head').map { |th| th.text.strip }
    assert_equal %w(Dance 5 4 3 2 1 1 2 3 F), headers.first(10)
  end
end
