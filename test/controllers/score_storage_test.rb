require "test_helper"

# Focused test for score value storage behavior
class ScoreStorageTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:one)
    Event.current = @event
    @judge = people(:Judy)
    @heat = heats(:one)  # Regular heat with entry
  end

  test "numeric scoring stores plain values not JSON" do
    @event.update!(open_scoring: '#')
    
    # Even with a name parameter (which is the heat ID), numeric scores should be plain
    post post_score_path(@judge), params: {
      heat: @heat.id,
      score: '95',
      name: @heat.id.to_s
    }, xhr: true
    
    assert_response :success
    
    score = Score.find_by(heat: @heat, judge: @judge)
    assert_equal '95', score.value
    assert_not score.value.start_with?('{'), "Numeric score should not be JSON"
  end

  test "letter scoring stores plain values not JSON" do
    @event.update!(closed_scoring: 'G')
    
    post post_score_path(@judge), params: {
      heat: @heat.id,
      score: 'S',
      name: @heat.id.to_s
    }, xhr: true
    
    assert_response :success
    
    score = Score.find_by(heat: @heat, judge: @judge)
    assert_equal 'S', score.value
    assert_not score.value.start_with?('{'), "Letter score should not be JSON"
  end

  test "4-part solo scoring stores JSON when enabled" do
    @event.update!(solo_scoring: '4')
    solo_heat = heats(:three)  # This is marked as Solo category
    
    # First score - technique
    post post_score_path(@judge), params: {
      heat: solo_heat.id,
      score: '22',
      name: 'technique'
    }, xhr: true
    
    assert_response :success
    
    score = Score.find_by(heat: solo_heat, judge: @judge)
    assert score.value.start_with?('{'), "4-part solo score should be JSON"
    parsed = JSON.parse(score.value)
    assert_equal '22', parsed['technique']
    
    # Second score - execution
    post post_score_path(@judge), params: {
      heat: solo_heat.id,
      score: '23',
      name: 'execution'
    }, xhr: true
    
    assert_response :success
    
    score.reload
    parsed = JSON.parse(score.value)
    assert_equal '22', parsed['technique'], "Should preserve existing value"
    assert_equal '23', parsed['execution'], "Should add new value"
  end

  test "single-value solo scoring stores plain values" do
    @event.update!(solo_scoring: '1')
    solo_heat = heats(:three)
    
    post post_score_path(@judge), params: {
      heat: solo_heat.id,
      score: '87'
    }, xhr: true
    
    assert_response :success
    
    score = Score.find_by(heat: solo_heat, judge: @judge)
    assert_equal '87', score.value
    assert_not score.value.start_with?('{'), "Single solo score should not be JSON"
  end
end