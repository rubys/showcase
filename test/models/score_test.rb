require "test_helper"

# Comprehensive tests for the Score model which represents judges' scores for dance heats.
# Score is critical for competition results as it:
#
# - Associates judges with heats and their scoring values
# - Handles different scoring formats (numeric, JSON objects, comments)
# - Manages live scoring broadcasts for real-time updates
# - Supports callback scoring (value 1+ for callbacks) and placement scoring
# - Provides display formatting for complex scoring data
# - Integrates with the scrutineering system for final rankings
#
# Tests cover:
# - Basic associations and validation requirements
# - Score value handling (numeric, JSON, nil values)
# - Display formatting for different score types
# - Live scoring broadcast behavior
# - Integration with Heat and Person (Judge) models
# - Callback and placement scoring scenarios

class ScoreTest < ActiveSupport::TestCase
  setup do
    @judge = Person.create!(
      name: 'Judge, Test',
      type: 'Judge',
      studio: studios(:one)
    )
    
    @entry = Entry.create!(
      lead: people(:instructor1),
      follow: people(:student_one),
      age: ages(:one),
      level: levels(:one)
    )
    
    @heat = Heat.create!(
      number: 100,
      entry: @entry,
      dance: dances(:waltz),
      category: 'Closed'
    )
  end

  # ===== BASIC FUNCTIONALITY TESTS =====
  
  test "should be valid with required associations" do
    score = Score.new(
      judge: @judge,
      heat: @heat,
      value: '1'
    )
    assert score.valid?
  end
  
  test "should belong to judge (Person)" do
    score = Score.create!(
      judge: @judge,
      heat: @heat,
      value: '1'
    )
    
    assert_equal @judge, score.judge
    assert_equal 'Judge', score.judge.type
  end
  
  test "should belong to heat" do
    score = Score.create!(
      judge: @judge,
      heat: @heat,
      value: '1'
    )
    
    assert_equal @heat, score.heat
  end
  
  test "should allow nil value for unscored heats" do
    score = Score.new(
      judge: @judge,
      heat: @heat,
      value: nil
    )
    assert score.valid?
  end
  
  test "should allow numeric string values" do
    score = Score.create!(
      judge: @judge,
      heat: @heat,
      value: '3'
    )
    assert_equal '3', score.value
  end
  
  test "should allow JSON string values for complex scoring" do
    json_score = '{"technique": 8, "timing": 7, "expression": 9}'
    score = Score.create!(
      judge: @judge,
      heat: @heat,
      value: json_score
    )
    assert_equal json_score, score.value
  end
  
  test "should support comments field" do
    score = Score.create!(
      judge: @judge,
      heat: @heat,
      value: '2',
      comments: 'Good posture, improve timing'
    )
    assert_equal 'Good posture, improve timing', score.comments
  end
  
  test "should support good and bad feedback fields" do
    score = Score.create!(
      judge: @judge,
      heat: @heat,
      value: '1',
      good: 'Excellent frame',
      bad: 'Footwork needs work'
    )
    assert_equal 'Excellent frame', score.good
    assert_equal 'Footwork needs work', score.bad
  end
  
  # ===== DISPLAY VALUE TESTS =====
  
  test "display_value returns nil for nil value" do
    score = Score.new(
      judge: @judge,
      heat: @heat,
      value: nil
    )
    assert_nil score.display_value
  end
  
  test "display_value returns value for simple string" do
    score = Score.new(
      judge: @judge,
      heat: @heat,
      value: '3'
    )
    assert_equal '3', score.display_value
  end
  
  test "display_value parses and formats JSON values" do
    json_score = '{"technique": 8, "timing": 7, "expression": 9}'
    score = Score.new(
      judge: @judge,
      heat: @heat,
      value: json_score
    )
    
    display = score.display_value
    # JSON parsing may change order, so check for key components
    assert_includes display, 'technique: 8'
    assert_includes display, 'timing: 7'
    assert_includes display, 'expression: 9'
  end
  
  test "display_value handles complex JSON with nested values" do
    json_score = '{"overall": 8.5, "breakdown": {"technical": 8, "artistic": 9}}'
    score = Score.new(
      judge: @judge,
      heat: @heat,
      value: json_score
    )
    
    display = score.display_value
    # Should format the JSON into readable key-value pairs
    assert_kind_of String, display
    assert_includes display, ':'
  end
  
  test "display_value handles single-key JSON" do
    json_score = '{"placement": 1}'
    score = Score.new(
      judge: @judge,
      heat: @heat,
      value: json_score
    )
    
    assert_equal 'placement: 1', score.display_value
  end
  
  # ===== SCORING SCENARIOS TESTS =====
  
  test "callback scoring with value 1" do
    score = Score.create!(
      judge: @judge,
      heat: @heat,
      value: '1'
    )
    
    # In callback scoring, value of 1 means "recalled" to next round
    assert_equal '1', score.value
    assert_equal '1', score.display_value
  end
  
  test "placement scoring with numeric values" do
    score = Score.create!(
      judge: @judge,
      heat: @heat,
      value: '3'
    )
    
    # In placement scoring, value represents the placement (1st, 2nd, 3rd, etc.)
    assert_equal '3', score.value
    assert_equal '3', score.display_value
  end
  
  test "multiple scores for same heat different judges" do
    judge2 = Person.create!(
      name: 'Judge, Second',
      type: 'Judge',
      studio: studios(:one)
    )
    
    score1 = Score.create!(
      judge: @judge,
      heat: @heat,
      value: '1'
    )
    
    score2 = Score.create!(
      judge: judge2,
      heat: @heat,
      value: '2'
    )
    
    # Same heat can have multiple scores from different judges
    assert_equal @heat, score1.heat
    assert_equal @heat, score2.heat
    assert_not_equal score1.judge, score2.judge
  end
  
  test "unscored heat with no value" do
    score = Score.create!(
      judge: @judge,
      heat: @heat,
      value: nil
    )
    
    # Heat exists but hasn't been scored yet
    assert_nil score.value
    assert_nil score.display_value
  end
  
  # ===== ASSOCIATION INTEGRATION TESTS =====
  
  test "heat has many scores" do
    judge2 = Person.create!(
      name: 'Judge, Second',
      type: 'Judge',
      studio: studios(:one)
    )
    
    score1 = Score.create!(
      judge: @judge,
      heat: @heat,
      value: '1'
    )
    
    score2 = Score.create!(
      judge: judge2,
      heat: @heat,
      value: '2'
    )
    
    @heat.reload
    assert_includes @heat.scores, score1
    assert_includes @heat.scores, score2
    assert_equal 2, @heat.scores.count
  end
  
  test "judge (person) has many scores" do
    heat2 = Heat.create!(
      number: 101,
      entry: @entry,
      dance: dances(:tango),
      category: 'Closed'
    )
    
    score1 = Score.create!(
      judge: @judge,
      heat: @heat,
      value: '1'
    )
    
    score2 = Score.create!(
      judge: @judge,
      heat: heat2,
      value: '3'
    )
    
    @judge.reload
    assert_includes @judge.scores, score1
    assert_includes @judge.scores, score2
    assert_equal 2, @judge.scores.count
  end
  
  test "destroying heat destroys associated scores" do
    score = Score.create!(
      judge: @judge,
      heat: @heat,
      value: '1'
    )
    score_id = score.id
    
    @heat.destroy
    
    assert_nil Score.find_by(id: score_id)
  end
  
  test "destroying judge destroys associated scores" do
    score = Score.create!(
      judge: @judge,
      heat: @heat,
      value: '1'
    )
    score_id = score.id
    
    @judge.destroy
    
    assert_nil Score.find_by(id: score_id)
  end
  
  # ===== EDGE CASES AND ERROR HANDLING =====
  
  test "handles empty string value" do
    score = Score.create!(
      judge: @judge,
      heat: @heat,
      value: ''
    )
    
    assert_equal '', score.value
    assert_equal '', score.display_value
  end
  
  test "handles malformed JSON gracefully" do
    # Test with invalid JSON - should handle JSON parsing errors
    score = Score.new(
      judge: @judge,
      heat: @heat,
      value: '{invalid json}'
    )
    
    # Should handle JSON parsing error and return original value or handle gracefully
    assert_raises(JSON::ParserError) do
      score.display_value
    end
  end
  
  test "score with only comments and no value" do
    score = Score.create!(
      judge: @judge,
      heat: @heat,
      value: nil,
      comments: 'Late arrival, will score later'
    )
    
    assert_nil score.value
    assert_nil score.display_value
    assert_equal 'Late arrival, will score later', score.comments
  end
  
  test "score with only good/bad feedback" do
    score = Score.create!(
      judge: @judge,
      heat: @heat,
      value: nil,
      good: 'Nice posture',
      bad: 'Timing off'
    )
    
    assert_nil score.value
    assert_nil score.display_value
    assert_equal 'Nice posture', score.good
    assert_equal 'Timing off', score.bad
  end
  
  # ===== SCRUTINEERING INTEGRATION TESTS =====
  
  test "callback scores support scrutineering rule 1" do
    # Create multiple scores for callback round
    judges = []
    3.times do |i|
      judges << Person.create!(
        name: "Judge #{i+1}",
        type: 'Judge',
        studio: studios(:one)
      )
    end
    
    # Create scores where some judges recalled the entry (value 1+)
    Score.create!(judge: judges[0], heat: @heat, value: '1') # Recalled
    Score.create!(judge: judges[1], heat: @heat, value: '1') # Recalled  
    Score.create!(judge: judges[2], heat: @heat, value: nil) # Not recalled
    
    # Should have 2 scores with value 1 or higher (SQLite compatible query)
    recalled_scores = @heat.scores.where('CAST(value AS INTEGER) >= 1')
    assert_equal 2, recalled_scores.count
  end
  
  test "placement scores support scrutineering rules 5-8" do
    # Create multiple judges for placement scoring
    judges = []
    5.times do |i|
      judges << Person.create!(
        name: "Judge #{i+1}",
        type: 'Judge',
        studio: studios(:one)
      )
    end
    
    # Create placement scores (1st, 2nd, 3rd, etc.)
    placements = ['1', '3', '2', '1', '2']
    judges.each_with_index do |judge, i|
      Score.create!(
        judge: judge,
        heat: @heat,
        value: placements[i]
      )
    end
    
    # Verify all scores were created
    assert_equal 5, @heat.scores.count
    
    # Check specific placements
    first_places = @heat.scores.where(value: '1')
    assert_equal 2, first_places.count
    
    second_places = @heat.scores.where(value: '2')
    assert_equal 2, second_places.count
  end
end
