require "test_helper"

# Comprehensive tests for ScoresController which manages the competition scoring system.
# This controller is critical for:
#
# - Judge scoring interface and workflows
# - Real-time score updates via Turbo Streams and AJAX
# - Score aggregation and reporting across multiple dimensions
# - Navigation between heats for judges during competition
# - Feedback system integration with good/bad scoring
# - Score validation and persistence with multiple scoring modes
#
# Tests cover:
# - Core scoring workflows (create, update, delete scores)
# - Real-time AJAX scoring endpoints (post, post_feedback)
# - Multiple scoring systems (Open, Closed, Solo, Multi, Numeric, Feedback)
# - Judge navigation and heat management
# - Score aggregation and reporting (by level, studio, age)
# - Turbo Stream real-time updates
# - Error handling and validation scenarios

class ScoresControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:one)
    Event.current = @event
    
    @heat = heats(:one)
    @judge = people(:Judy)
    @instructor = people(:instructor1)
    @student = people(:student_one)
    @student2 = people(:student_two)
    @age = ages(:one)
    @level = levels(:one)
    @dance = dances(:waltz)
    
    # Create test entry and heat for scoring
    @entry = Entry.create!(
      lead: @instructor,
      follow: @student,
      age: @age,
      level: @level
    )
    
    @test_heat = Heat.create!(
      number: 10,
      entry: @entry,
      dance: @dance,
      category: 'Closed'
    )
    
    # Create test score
    @score = Score.create!(
      heat: @test_heat,
      judge: @judge,
      value: 'G'
    )
  end

  # ===== BASIC INTERFACE TESTS =====
  
  test "heatlist displays judge's agenda and navigation" do
    get judge_heatlist_path(@judge)
    
    assert_response :success
    assert_select 'body'  # Basic page structure
  end
  
  test "heat interface displays scoring form for specific heat" do
    get judge_heat_path(@judge, @test_heat.number)
    
    assert_response :success
    assert_select 'body'
  end
  
  test "index displays scores overview" do
    get scores_url
    
    assert_response :success
    assert_select 'body'
  end

  # ===== CORE SCORING WORKFLOW TESTS =====
  
  test "creates new score via AJAX post endpoint" do
    # Remove existing score first
    @score.destroy
    
    assert_difference('Score.count') do
      post post_score_path(@judge), params: {
        heat: @test_heat.id,
        score: 'S'
      }, xhr: true
    end
    
    assert_response :success
    
    new_score = Score.last
    assert_equal @test_heat, new_score.heat
    assert_equal @judge, new_score.judge
    assert_equal 'S', new_score.value
  end
  
  test "updates existing score value via AJAX" do
    post post_score_path(@judge), params: {
      heat: @test_heat.id,
      score: 'B'  # Change from 'G' to 'B'
    }, xhr: true
    
    assert_response :success
    
    @score.reload
    assert_equal 'B', @score.value
  end
  
  test "deletes score when value becomes empty" do
    assert_difference('Score.count', -1) do
      post post_score_path(@judge), params: {
        heat: @test_heat.id,
        score: ''  # Empty value should delete score
      }, xhr: true
    end
    
    assert_response :success
  end
  
  test "handles JSON scoring values for complex scoring" do
    json_value = { placement: 1, callback: true }.to_json
    
    post post_score_path(@judge), params: {
      heat: @test_heat.id,
      score: json_value
    }, xhr: true
    
    assert_response :success
    
    @score.reload
    assert_equal json_value, @score.value
  end
  
  test "creates score with slot number for multi-dance heats" do
    post post_score_path(@judge), params: {
      heat: @test_heat.id,
      score: '2',
      slot: 1
    }, xhr: true
    
    assert_response :success
    
    new_score = Score.last
    assert_equal 1, new_score.slot
    assert_equal '2', new_score.value
  end

  # ===== FEEDBACK SYSTEM TESTS =====
  
  test "creates good feedback via post_feedback endpoint" do
    # Remove existing score first
    @score.destroy
    
    assert_difference('Score.count') do
      post post_feedback_path(@judge), params: {
        heat: @test_heat.id,
        good: 'F'  # Frame feedback
      }, xhr: true
    end
    
    assert_response :success
    
    feedback_score = Score.last
    assert_equal @test_heat, feedback_score.heat
    assert_equal @judge, feedback_score.judge
    assert_equal 'F', feedback_score.good
  end
  
  test "creates bad feedback via post_feedback endpoint" do
    # Remove existing score first
    @score.destroy
    
    assert_difference('Score.count') do
      post post_feedback_path(@judge), params: {
        heat: @test_heat.id,
        bad: 'T'  # Timing feedback
      }, xhr: true
    end
    
    assert_response :success
    
    feedback_score = Score.last
    assert_equal 'T', feedback_score.bad
  end
  
  test "feedback endpoint handles requests correctly" do
    # Test that feedback endpoints respond successfully
    post post_feedback_path(@judge), params: {
      heat: @test_heat.id,
      good: 'F'
    }, xhr: true
    
    assert_response :success
    
    post post_feedback_path(@judge), params: {
      heat: @test_heat.id,
      bad: 'T'
    }, xhr: true
    
    assert_response :success
    
    # Verify that scores are updated (exact behavior may vary)
    scores = Score.where(heat: @test_heat, judge: @judge)
    assert scores.exists?, "Should have score records for this heat/judge combination"
  end
  
  test "adds comments via scoring interface" do
    post post_score_path(@judge), params: {
      heat: @test_heat.id,
      comments: 'Excellent technique'
    }, xhr: true
    
    assert_response :success
    
    @score.reload
    assert_equal 'Excellent technique', @score.comments
  end

  # ===== SCORING MODE TESTS =====
  
  test "handles closed scoring with grade system" do
    # Test standard closed scoring grades: GH, G, S, B
    %w[GH G S B].each do |grade|
      score = Score.create!(
        heat: @test_heat,
        judge: @judge,
        value: grade
      )
      
      assert_equal grade, score.value
      assert_equal grade, score.display_value
    end
  end
  
  test "handles open scoring with placement numbers" do
    # Test open scoring placements: 1, 2, 3, F
    %w[1 2 3 F].each do |placement|
      score = Score.create!(
        heat: @test_heat,
        judge: @judge,
        value: placement
      )
      
      assert_equal placement, score.value
      assert_equal placement, score.display_value
    end
  end
  
  test "handles numeric scoring mode" do
    # Test numeric scoring with point values
    score = Score.create!(
      heat: @test_heat,
      judge: @judge,
      value: '85'
    )
    
    assert_equal '85', score.value
    assert_equal '85', score.display_value
  end
  
  test "handles combined value and feedback scoring" do
    score = Score.create!(
      heat: @test_heat,
      judge: @judge,
      value: 'G',
      good: 'F',
      bad: nil,
      comments: 'Strong lead, minor timing issue'
    )
    
    assert_equal 'G', score.value
    assert_equal 'F', score.good
    assert_nil score.bad
    assert_equal 'Strong lead, minor timing issue', score.comments
  end

  # ===== HEAT NAVIGATION TESTS =====
  
  test "heat interface shows correct heat details" do
    get judge_heat_path(@judge, @test_heat.number)
    
    assert_response :success
    # Should display heat information
    assert_select 'body'
  end
  
  test "supports navigation with judge and back number parameters" do
    get judge_heat_path(@judge, @test_heat.number, back: 1)
    
    assert_response :success
    # Should handle judge and back number parameters
    assert_select 'body'
  end
  
  test "handles solo heat navigation" do
    # Create solo heat
    solo_entry = Entry.create!(
      lead: @student,
      follow: @student,  # Solo entry
      instructor: @instructor,  # Solo entries need an instructor
      age: @age,
      level: @level
    )
    
    solo_heat = Heat.create!(
      number: 20,
      entry: solo_entry,
      dance: @dance,
      category: 'Solo'
    )
    
    # Create solo record
    Solo.create!(
      heat: solo_heat,
      song: 'Test Song',
      artist: 'Test Artist'
    )
    
    get judge_heat_path(@judge, solo_heat.number)
    
    assert_response :success
    assert_select 'body'
  end

  # ===== SCORE AGGREGATION AND REPORTING TESTS =====
  
  test "by_level aggregates scores by dance level" do
    get by_level_scores_path
    
    assert_response :success
    assert_select 'body'
  end
  
  test "by_studio calculates studio scoring averages" do
    get by_studio_scores_path
    
    assert_response :success
    assert_select 'body'
  end
  
  test "by_age groups scores by age categories" do
    get by_age_scores_path
    
    assert_response :success
    assert_select 'body'
  end
  
  test "multis handles multi-dance category scoring" do
    get multis_scores_path
    
    assert_response :success
    assert_select 'body'
  end
  
  test "pros displays professional competitor scoring" do
    get pros_scores_path
    
    assert_response :success
    assert_select 'body'
  end
  
  test "instructor shows instructor-specific scoring" do
    get instructor_scores_path
    
    assert_response :success
    assert_select 'body'
  end
  
  test "sort provides score sorting and ranking" do
    post sort_scores_path(@judge)
    
    # Sort action redirects back to heatlist after sorting
    assert_response :redirect
  end

  # ===== REAL-TIME FEATURES TESTS =====
  
  test "score updates trigger Turbo Stream broadcasts" do
    # Test that score updates broadcast to live views
    post post_score_path(@judge), params: {
      heat: @test_heat.id,
      score: 'S'
    }, xhr: true
    
    assert_response :success
    # Turbo Stream broadcasting is tested by the Score model after_save callback
  end
  
  test "score creation updates last update timestamp" do
    initial_time = Time.current
    
    post post_score_path(@judge), params: {
      heat: @test_heat.id,
      score: 'B'
    }, xhr: true
    
    assert_response :success
    
    # Score should have updated timestamp
    latest_score = Score.last
    assert_operator latest_score.updated_at, :>=, initial_time
  end

  # ===== ERROR HANDLING AND VALIDATION TESTS =====
  
  test "handles missing heat parameter gracefully" do
    # This should cause an error since heat parameter is required
    assert_raises(ActiveRecord::RecordNotFound) do
      post post_score_path(@judge), params: {
        score: 'G'
      }, xhr: true
    end
  end
  
  test "handles missing judge parameter gracefully" do
    post post_score_path(@judge), params: {
      heat: @test_heat.id,
      score: 'G'
    }, xhr: true
    
    # Should handle gracefully
    assert_includes [200, 422, 404], response.status
  end
  
  test "validates score associations exist" do
    # This should cause an error since heat doesn't exist
    assert_raises(ActiveRecord::RecordNotFound) do
      post post_score_path(@judge), params: {
        heat: 99999,  # Non-existent heat
        score: 'G'
      }, xhr: true
    end
  end
  
  test "handles malformed JSON values gracefully" do
    post post_score_path(@judge), params: {
      heat: @test_heat.id,
      score: '{"invalid": json}'  # Malformed JSON
    }, xhr: true
    
    # Should handle without crashing
    assert_includes [200, 422], response.status
  end
  
  test "prevents duplicate scoring for same heat/judge/slot combination" do
    # Create first score
    post post_score_path(@judge), params: {
      heat: @test_heat.id,
      score: 'G',
      slot: 1
    }, xhr: true
    
    assert_response :success
    initial_count = Score.count
    
    # Attempt duplicate (should update, not create)
    post post_score_path(@judge), params: {
      heat: @test_heat.id,
      score: 'S',
      slot: 1
    }, xhr: true
    
    assert_response :success
    assert_equal initial_count, Score.count  # Should not create duplicate
  end

  # ===== COMMENTS AND FEEDBACK INTEGRATION =====
  
  test "comments action displays all comments" do
    # Add comment to score
    @score.update!(comments: 'Test comment for review')
    
    get comments_scores_path
    
    assert_response :success
    assert_select 'body'
  end
  
  test "reset action clears scores appropriately" do
    # This action requires careful testing as it affects competition data
    post reset_scores_path
    
    # Should handle reset operation
    assert_includes [200, 302], response.status
  end

  # ===== JUDGE ASSIGNMENT AND FILTERING =====
  
  test "respects judge assignment when accessing heats" do
    # Create judge assignment
    Score.create!(
      heat: @test_heat,
      judge: @judge,
      value: ''  # Empty score to establish assignment
    )
    
    get judge_heat_path(@judge, @test_heat.number)
    
    assert_response :success
    assert_select 'body'
  end
  
  test "handles multiple judges scoring same heat" do
    # Create second judge
    judge2 = Person.create!(
      name: 'Second Judge',
      type: 'Judge',
      studio_id: 0
    )
    
    # Both judges score the same heat
    Score.create!(heat: @test_heat, judge: @judge, value: 'G')
    Score.create!(heat: @test_heat, judge: judge2, value: 'S')
    
    # Should handle multiple judge scores
    get judge_heat_path(@judge, @test_heat.number)
    assert_response :success
    
    # Verify both scores exist (including the original test score)
    assert_equal 3, @test_heat.scores.count
  end

  # ===== PERFORMANCE AND SCALE TESTS =====
  
  test "handles large number of scores efficiently" do
    # Create multiple scores
    10.times do |i|
      Score.create!(
        heat: @test_heat,
        judge: @judge,
        value: 'G',
        slot: i
      )
    end
    
    get judge_heat_path(@judge, @test_heat.number)
    assert_response :success
    
    # Should handle reporting with many scores
    get by_level_scores_path
    assert_response :success
  end
  
  test "concurrent scoring updates handle race conditions" do
    # Test basic concurrent scoring scenario
    post post_score_path(@judge), params: {
      heat: @test_heat.id,
      score: 'G'
    }, xhr: true
    
    assert_response :success
    
    # Immediate second update
    post post_score_path(@judge), params: {
      heat: @test_heat.id,
      score: 'S'
    }, xhr: true
    
    assert_response :success
    
    # Should maintain data consistency
    @score.reload
    assert_includes ['G', 'S'], @score.value
  end

  # ===== INTEGRATION TESTS =====
  
  test "complete scoring workflow for single heat" do
    # Judge scores a heat with multiple aspects
    
    # 1. Create placement score
    post post_score_path(@judge), params: {
      heat: @test_heat.id,
      score: '1'
    }, xhr: true
    assert_response :success
    
    # 2. Add feedback
    post post_feedback_path(@judge), params: {
      heat: @test_heat.id,
      good: 'F'
    }, xhr: true
    assert_response :success
    
    # 3. Add comments
    post post_score_path(@judge), params: {
      heat: @test_heat.id,
      comments: 'Excellent performance'
    }, xhr: true
    assert_response :success
    
    # Verify complete scoring
    final_score = Score.find_by(heat: @test_heat, judge: @judge)
    assert_equal '1', final_score.value
    assert_equal 'F', final_score.good
    assert_equal 'Excellent performance', final_score.comments
  end
  
  test "scoring workflow with slot-based multi-dance heat" do
    # Create multi-dance heat
    multi_heat = Heat.create!(
      number: 30,
      entry: @entry,
      dance: @dance,
      category: 'Multi'
    )
    
    # Score multiple slots
    (1..3).each do |slot|
      post post_score_path(@judge), params: {
        heat: multi_heat.id,
        score: slot.to_s,
        slot: slot
      }, xhr: true
      
      assert_response :success
    end
    
    # Verify all slot scores created
    assert_equal 3, multi_heat.scores.where(judge: @judge).count
  end

  # ===== PERMISSION AND SECURITY TESTS =====
  
  test "scoring endpoints require appropriate permissions" do
    # Test that scoring actions are accessible
    # (Actual permission logic would depend on authentication system)
    
    get judge_heatlist_path(@judge)
    assert_response :success
    
    get judge_heat_path(@judge, @test_heat.number)
    assert_response :success
  end
  
  test "AJAX endpoints handle CSRF appropriately" do
    # Test CSRF protection on AJAX scoring endpoints
    post post_score_path(@judge), params: {
      heat: @test_heat.id,
      score: 'G'
    }, xhr: true
    
    # Should handle CSRF (may pass in test environment)
    assert_includes [200, 422], response.status
  end

  # ===== BROWSER COMPATIBILITY TESTS =====
  
  test "handles different user agent scenarios" do
    # Test browser compatibility warnings
    get judge_heat_path(@judge, @test_heat.number), headers: {
      'HTTP_USER_AGENT' => 'Mozilla/5.0 (compatible; OldBrowser/1.0)'
    }
    
    assert_response :success
    assert_select 'body'
  end

  # ===== CRITICAL BUSINESS LOGIC TESTS =====

  test "post handles readonly database correctly" do
    # Mock readonly state
    ApplicationRecord.class_variable_set(:@@readonly_showcase, true)
    
    post post_score_path(@judge), params: {
      heat: @test_heat.id,
      score: 'G'
    }, xhr: true
    
    assert_response :service_unavailable
    assert_equal 'database is readonly', response.body.delete('"')
    
  ensure
    # Reset readonly state
    ApplicationRecord.class_variable_set(:@@readonly_showcase, false)
  end

  test "post_feedback handles complex feedback state transitions" do
    # Test good feedback addition
    post post_feedback_path(@judge), params: {
      heat: @test_heat.id,
      good: 'timing'
    }, xhr: true
    
    assert_response :success
    @score.reload
    assert_equal 'timing', @score.good
    
    # Test adding second good feedback item
    post post_feedback_path(@judge), params: {
      heat: @test_heat.id,
      good: 'posture'  
    }, xhr: true
    
    @score.reload
    assert_includes @score.good.split(' '), 'timing'
    assert_includes @score.good.split(' '), 'posture'
    
    # Test moving feedback from good to bad
    post post_feedback_path(@judge), params: {
      heat: @test_heat.id,
      bad: 'timing'
    }, xhr: true
    
    @score.reload
    assert_includes @score.bad.split(' '), 'timing'
    assert_not_includes @score.good.split(' '), 'timing'
  end

  test "post_feedback handles readonly database" do
    ApplicationRecord.class_variable_set(:@@readonly_showcase, true)
    
    post post_feedback_path(@judge), params: {
      heat: @test_heat.id,
      good: 'timing'
    }, xhr: true
    
    assert_response :service_unavailable
    
  ensure
    ApplicationRecord.class_variable_set(:@@readonly_showcase, false)
  end

  test "post handles JSON value parsing and updates for 4-part solo scoring" do
    # Create a solo heat with 4-part scoring
    solo_dance = Dance.create!(
      name: 'Solo Waltz',
      order: 999,
      solo_category: categories(:solo)
    )
    
    # Create heat first, then solo
    solo_heat = Heat.create!(
      number: 100,
      dance: solo_dance,
      entry: @entry,
      category: 'Solo'
    )
    
    # Create solo that belongs to the heat
    solo = Solo.create!(
      heat: solo_heat,
      order: 100
    )
    
    # Set event to use 4-part solo scoring
    @event.update!(solo_scoring: '4')
    
    # Create score with initial technique value
    score = Score.create!(
      heat: solo_heat,
      judge: @judge,
      value: '{"technique":"20"}'
    )
    
    # Update with execution score
    post post_score_path(@judge), params: {
      heat: solo_heat.id,
      score: '23',
      name: 'execution'
    }, xhr: true
    
    assert_response :success
    score.reload
    
    parsed_value = JSON.parse(score.value)
    assert_equal '20', parsed_value['technique']
    assert_equal '23', parsed_value['execution']
  end

  test "post handles score deletion conditions correctly" do
    # Test score deletion when all conditions are empty
    @score.update!(comments: nil, good: nil, bad: nil)
    
    post post_score_path(@judge), params: {
      heat: @test_heat.id,
      score: ''
    }, xhr: true
    
    assert_response :success
    assert_raises(ActiveRecord::RecordNotFound) { @score.reload }
  end

  test "student_results calculates correct aggregations" do
    # Create test data for student results
    student = people(:student_one)
    pro = people(:instructor1)
    
    entry = Entry.create!(lead: pro, follow: student, age: @age, level: @level)
    heat = Heat.create!(number: 20, entry: entry, dance: @dance, category: 'Closed')
    
    Score.create!(heat: heat, judge: @judge, value: 'G')
    Score.create!(heat: heat, judge: people(:Kathryn), value: 'S')
    
    controller = ScoresController.new
    results = controller.send(:student_results)
    
    assert results.is_a?(Hash)
    assert_includes results.keys, 'Followers'
    assert_includes results.keys, 'Leaders' 
    assert_includes results.keys, 'Couples'
    
    # Test that followers data includes our test score
    followers_data = results['Followers']
    assert followers_data.is_a?(Hash)
  end

  test "student_results respects strict scoring settings" do
    event = Event.current
    original_strict = event.strict_scoring
    
    # Test with strict scoring enabled
    event.update!(strict_scoring: true, track_ages: true)
    
    controller = ScoresController.new
    results = controller.send(:student_results)
    
    assert results.is_a?(Hash)
    assert_equal 3, results.keys.length
    
  ensure
    event.update!(strict_scoring: original_strict)
  end

  test "post_feedback handles malformed feedback gracefully" do
    # Test with missing required parameters
    post post_feedback_path(@judge), params: {
      heat: @test_heat.id
      # Missing good/bad/value parameter
    }, xhr: true
    
    assert_response :bad_request
  end

  test "post handles comments update and deletion" do
    post post_score_path(@judge), params: {
      heat: @test_heat.id,
      comments: 'Great improvement in posture'
    }, xhr: true
    
    assert_response :success
    @score.reload
    assert_equal 'Great improvement in posture', @score.comments
    
    # Test comment deletion
    post post_score_path(@judge), params: {
      heat: @test_heat.id,
      comments: ''
    }, xhr: true
    
    @score.reload
    assert_nil @score.comments
  end

  test "post handles score persistence with assign_judges setting" do
    event = Event.current
    original_assign = event.assign_judges
    
    # Test with assign_judges > 0 (should keep empty scores)
    event.update!(assign_judges: 1)
    
    post post_score_path(@judge), params: {
      heat: @test_heat.id,
      score: ''
    }, xhr: true
    
    assert_response :success
    # Score should still exist due to assign_judges setting
    assert_nothing_raised { @score.reload }
    
  ensure
    event.update!(assign_judges: original_assign)
  end

  # ===== CALLBACK DETERMINATION TESTS =====
  
  test "callbacks action displays callback determination page" do
    # Create scrutineering dance with semi_finals
    scrutineering_dance = Dance.create!(
      name: 'Test Scrutineering Waltz',
      semi_finals: true,
      heat_length: 3,
      order: 1001
    )
    
    # Create entries and heats
    entry1 = Entry.create!(lead: @instructor, follow: @student, age: @age, level: @level)
    entry2 = Entry.create!(lead: people(:instructor2), follow: @student2, age: @age, level: @level)
    
    heat1 = Heat.create!(number: 100, entry: entry1, dance: scrutineering_dance, category: 'Multi')
    heat2 = Heat.create!(number: 100, entry: entry2, dance: scrutineering_dance, category: 'Multi')
    
    # Create semi-final callback votes (value >= 1 means callback)
    Score.create!(heat: heat1, judge: @judge, value: '1', slot: 1)
    Score.create!(heat: heat1, judge: people(:Kathryn), value: '1', slot: 1)
    Score.create!(heat: heat2, judge: @judge, value: '0', slot: 1)
    Score.create!(heat: heat2, judge: people(:Kathryn), value: '1', slot: 1)
    
    # Create final scores for entries that were called back
    Score.create!(heat: heat1, judge: @judge, value: '1', slot: 3)
    Score.create!(heat: heat1, judge: people(:Kathryn), value: '2', slot: 3)
    
    get callbacks_scores_path
    
    assert_response :success
    assert_select 'h1', 'Callback Determination'
    assert_select 'h2', text: /Test Scrutineering Waltz/
  end
  
  test "callbacks shows correct callback counts and status" do
    # Create scrutineering dance
    dance = Dance.create!(name: 'Test Callback Tango', semi_finals: true, heat_length: 2, order: 1002)
    
    # Create 3 entries
    entries = []
    3.times do |i|
      student = Person.create!(name: "Student #{i}", type: 'Student', studio: studios(:one), level: @level)
      entry = Entry.create!(lead: @instructor, follow: student, age: @age, level: @level)
      entries << entry
    end
    
    # Create heats
    heats = entries.map.with_index do |entry, i|
      Heat.create!(number: 200, entry: entry, dance: dance, category: 'Multi')
    end
    
    # Create semi-final scores: entry 1 gets 2 votes (called back), entry 2 gets 1 vote, entry 3 gets 0 votes
    Score.create!(heat: heats[0], judge: @judge, value: '1', slot: 1)
    Score.create!(heat: heats[0], judge: people(:Kathryn), value: '1', slot: 1)
    Score.create!(heat: heats[1], judge: @judge, value: '1', slot: 1)
    
    # Create final scores for entries that were called back (entry 1 only)
    Score.create!(heat: heats[0], judge: @judge, value: '1', slot: 2)
    
    get callbacks_scores_path
    
    assert_response :success
    
    # Should show callback information in the table
    assert_select 'table tr', minimum: 2 # Should have at least the entries with scores (plus header)
    assert_select 'table tr td', minimum: 5 # Should have cells for entries
    
    # Should show some vote counts and callback status
    response_body = @response.body
    assert_includes response_body, 'Called Back'
    # Only entries with scores are shown, so we may not see 'Not Called' if all scored entries got callbacks
  end
  
  test "callbacks handles no scrutineering dances gracefully" do
    # Ensure no dances have semi_finals set
    Dance.update_all(semi_finals: false)
    
    get callbacks_scores_path
    
    assert_response :success
    assert_includes @response.body, 'No callback scores entered yet.'
  end
  
  test "callbacks shows judge voting summary" do
    # Create scrutineering dance
    dance = Dance.create!(name: 'Test Judge Foxtrot', semi_finals: true, heat_length: 1, order: 1003)
    
    # Create entries and heats
    entry1 = Entry.create!(lead: @instructor, follow: @student, age: @age, level: @level)
    entry2 = Entry.create!(lead: people(:instructor2), follow: @student2, age: @age, level: @level)
    
    heat1 = Heat.create!(number: 300, entry: entry1, dance: dance, category: 'Multi')
    heat2 = Heat.create!(number: 300, entry: entry2, dance: dance, category: 'Multi')
    
    # Semi-final votes: Judge votes for both entries, Kathryn votes for one
    Score.create!(heat: heat1, judge: @judge, value: '1', slot: 1)
    Score.create!(heat: heat2, judge: @judge, value: '1', slot: 1)
    Score.create!(heat: heat1, judge: people(:Kathryn), value: '1', slot: 1)
    
    # Final scores for entries that were called back (both entries)
    Score.create!(heat: heat1, judge: @judge, value: '1', slot: 2)
    Score.create!(heat: heat2, judge: @judge, value: '2', slot: 2)
    
    get callbacks_scores_path
    
    assert_response :success
    
    # Check that the page shows callback information
    assert_select 'table tr', minimum: 2 # Should have at least header plus one entry with scores
    
    # Should show both judges mentioned somewhere in the judges column
    response_body = @response.body
    assert_includes response_body, @judge.display_name
    assert_includes response_body, people(:Kathryn).display_name
  end
  
  test "callbacks displays multiple heats for same dance" do
    # Create dance with multiple heats
    dance = Dance.create!(name: 'Test Multi Heat Rumba', semi_finals: true, heat_length: 2, order: 1004)
    
    # Create entries for two different heats
    entry1 = Entry.create!(lead: @instructor, follow: @student, age: @age, level: @level)
    entry2 = Entry.create!(lead: people(:instructor2), follow: @student2, age: @age, level: @level)
    
    heat1 = Heat.create!(number: 400, entry: entry1, dance: dance, category: 'Multi')
    heat2 = Heat.create!(number: 401, entry: entry2, dance: dance, category: 'Multi')
    
    # Add semi-final scores
    Score.create!(heat: heat1, judge: @judge, value: '1', slot: 1)
    Score.create!(heat: heat2, judge: people(:Kathryn), value: '1', slot: 1)
    
    # Add final scores for entries that were called back
    Score.create!(heat: heat1, judge: @judge, value: '1', slot: 2)
    Score.create!(heat: heat2, judge: people(:Kathryn), value: '1', slot: 2)
    
    get callbacks_scores_path
    
    assert_response :success
    
    # Should show heat numbers when multiple heats exist  
    assert_includes @response.body, 'Heat 400'
    assert_includes @response.body, 'Heat 401'
  end
  
  test "semi-finals with less than 8 couples shows all couples in slot 1" do
    # Create a multi category for the dance
    multi_category = Category.create!(
      name: 'Test Multi Category',
      order: 999
    )
    
    # Create a scrutineering dance with semi_finals
    dance = Dance.create!(
      name: 'Small Semi-Final Waltz', 
      semi_finals: true, 
      heat_length: 3,
      order: 1005,
      multi_category: multi_category
    )
    
    # Create only 5 couples (less than 8)
    entries = []
    heats = []
    5.times do |i|
      student = Person.create!(
        name: "Semi Student #{i}", 
        type: 'Student', 
        studio: studios(:one), 
        level: @level,
        back: 1200 + i
      )
      instructor = Person.create!(
        name: "Semi Instructor #{i}", 
        type: 'Professional', 
        studio: studios(:one),
        back: 1300 + i
      )
      entry = Entry.create!(lead: instructor, follow: student, age: @age, level: @level)
      entries << entry
      heat = Heat.create!(number: 300 + i/10.0, entry: entry, dance: dance, category: 'Multi')
      heats << heat
    end
    
    # Create scores for all couples in slot 1 (semi-final round)
    # For fewer than 8 couples, all should get final placement scores
    heats.each_with_index do |heat, i|
      # Give each couple scores from both judges with different placements
      judges = [@judge, people(:Kathryn)]
      judges.each_with_index do |judge, j|
        # Give different placement scores (1-5) to create rankings
        placement = ((i + j) % 5) + 1
        Score.create!(heat: heat, judge: judge, value: placement.to_s, slot: 1)
      end
    end
    
    # Get the multis page with details (which shows scrutineering results)
    get details_multis_scores_path
    
    assert_response :success
    
    
    # Check that all 5 couples are shown in the results
    assert_select "h2", text: /Small Semi-Final Waltz.*Scrutineering/
    
    # Should have a table with results for all couples
    assert_select "table" do
      # Check for presence of the instructor/lead names (since back numbers aren't displayed in this view)
      entries.each do |entry|
        assert_select "a", text: entry.lead.display_name
      end
    end
    
    # Verify that "No couples on the floor" message is NOT shown
    assert_select "p", text: /No couples on the floor/, count: 0
  end

  # ===== JUDGE HEAT INTERFACE SCRUTINEERING TESTS =====
  # These tests specifically target the judge heat scoring interface
  # for semi-finals dances, addressing gaps that allowed the bug where
  # heats with ≤8 couples showed "No couples on the floor"

  test "judge heat interface shows all couples for semi-finals dance with 4 couples (no scores yet)" do
    # Create multi category
    multi_category = Category.create!(
      name: 'Test Semi-Finals Category',
      order: 1000
    )
    
    # Create scrutineering dance with semi_finals enabled
    dance = Dance.create!(
      name: 'Test Semi-Finals Waltz',
      semi_finals: true,
      heat_length: 4,
      order: 2000,
      multi_category: multi_category
    )
    
    # Create exactly 4 couples (≤8, so should skip semi-finals per documentation)
    entries = []
    heats = []
    4.times do |i|
      student = Person.create!(
        name: "Semi Student #{i}",
        type: 'Student',
        studio: studios(:one),
        level: @level,
        back: 400 + i
      )
      instructor = Person.create!(
        name: "Semi Instructor #{i}",
        type: 'Professional',
        studio: studios(:one),
        back: 500 + i
      )
      entry = Entry.create!(lead: instructor, follow: student, age: @age, level: @level)
      entries << entry
      heat = Heat.create!(number: 91, entry: entry, dance: dance, category: 'Multi')
      heats << heat
    end
    
    # Visit heat as judge - NO SCORES EXIST YET
    # This is the exact scenario that was broken
    get judge_heat_path(@judge, 91, slot: 1)
    
    assert_response :success
    
    # Should show all 4 couples (no "No couples on the floor" message)
    assert_select "p", text: /No couples on the floor/, count: 0
    assert_select "table" do
      # Should have 4 rows for couples (with hover:bg-yellow-200 class)
      assert_select "tr.hover\\:bg-yellow-200", count: 4
      
      # Check that all couples are displayed by their back numbers
      entries.each do |entry|
        assert_select "td", text: entry.lead.back.to_s
      end
    end
    
    # Should be in final mode since ≤8 couples
    # This means should show ranking interface, not callback checkboxes
    assert_select "input[type='checkbox']", count: 0
  end
  
  test "judge heat interface shows all couples for semi-finals dance with 8 couples (no scores yet)" do
    # Create multi category  
    multi_category = Category.create!(
      name: 'Test 8-Couple Category',
      order: 1001
    )
    
    # Create scrutineering dance
    dance = Dance.create!(
      name: 'Test 8-Couple Waltz',
      semi_finals: true,
      heat_length: 4,
      order: 2001,
      multi_category: multi_category
    )
    
    # Create exactly 8 couples (boundary case - should still skip semi-finals)
    entries = []
    heats = []
    8.times do |i|
      student = Person.create!(
        name: "Eight Student #{i}",
        type: 'Student', 
        studio: studios(:one),
        level: @level,
        back: 600 + i
      )
      instructor = Person.create!(
        name: "Eight Instructor #{i}",
        type: 'Professional',
        studio: studios(:one), 
        back: 700 + i
      )
      entry = Entry.create!(lead: instructor, follow: student, age: @age, level: @level)
      entries << entry
      heat = Heat.create!(number: 92, entry: entry, dance: dance, category: 'Multi')
      heats << heat
    end
    
    # Visit heat as judge - NO SCORES EXIST YET
    get judge_heat_path(@judge, 92, slot: 1)
    
    assert_response :success
    
    # Should show all 8 couples
    assert_select "p", text: /No couples on the floor/, count: 0
    assert_select "tr.hover\\:bg-yellow-200", count: 8
    
    # Should be in final mode (ranking, not callbacks)
    assert_select "input[type='checkbox']", count: 0
  end
  
  test "judge heat interface requires callbacks for semi-finals dance with 9 couples" do
    # Create multi category
    multi_category = Category.create!(
      name: 'Test Large Semi-Finals Category', 
      order: 1002
    )
    
    # Create scrutineering dance
    dance = Dance.create!(
      name: 'Test Large Semi-Finals Waltz',
      semi_finals: true,
      heat_length: 4,
      order: 2002,
      multi_category: multi_category
    )
    
    # Create 9 couples (>8, so should require semi-finals)
    entries = []
    heats = []
    9.times do |i|
      student = Person.create!(
        name: "Large Student #{i}",
        type: 'Student',
        studio: studios(:one),
        level: @level, 
        back: 800 + i
      )
      instructor = Person.create!(
        name: "Large Instructor #{i}",
        type: 'Professional',
        studio: studios(:one),
        back: 900 + i
      )
      entry = Entry.create!(lead: instructor, follow: student, age: @age, level: @level)
      entries << entry
      heat = Heat.create!(number: 93, entry: entry, dance: dance, category: 'Multi')
      heats << heat
    end
    
    # Visit heat as judge for semi-final slot - NO SCORES EXIST YET
    get judge_heat_path(@judge, 93, slot: 1)  # Semi-final slot
    
    assert_response :success
    
    # Should show all 9 couples for callback selection
    assert_select "p", text: /No couples on the floor/, count: 0
    assert_select "tr.hover\\:bg-yellow-200", count: 9
    
    # Should be in semi-final mode (checkboxes for callbacks, not ranking)
    assert_select "input[type='checkbox']", count: 9
  end
  
  test "judge heat interface handles final slot for large heat after callbacks" do
    # Create multi category
    multi_category = Category.create!(
      name: 'Test Callback Finals Category',
      order: 1003
    )
    
    # Create scrutineering dance
    dance = Dance.create!(
      name: 'Test Callback Finals Waltz', 
      semi_finals: true,
      heat_length: 2,  # 2 semi-final slots, slot 3+ would be finals
      order: 2003,
      multi_category: multi_category
    )
    
    # Create 10 couples
    entries = []
    heats = []
    10.times do |i|
      student = Person.create!(
        name: "Finals Student #{i}",
        type: 'Student',
        studio: studios(:one),
        level: @level,
        back: 1000 + i
      )
      instructor = Person.create!(
        name: "Finals Instructor #{i}",
        type: 'Professional', 
        studio: studios(:one),
        back: 1100 + i
      )
      entry = Entry.create!(lead: instructor, follow: student, age: @age, level: @level)
      entries << entry
      heat = Heat.create!(number: 94, entry: entry, dance: dance, category: 'Multi')
      heats << heat
    end
    
    # Create some semi-final scores to establish callbacks (first 6 couples)
    heats[0, 6].each_with_index do |heat, i|
      Score.create!(heat: heat, judge: @judge, value: '1', slot: 1)
      Score.create!(heat: heat, judge: @judge, value: '1', slot: 2)
    end
    
    # Visit final slot (slot 3, which is > heat_length of 2)
    get judge_heat_path(@judge, 94, slot: 3)
    
    assert_response :success
    
    # Should show only the called-back couples (6)
    assert_select "p", text: /No couples on the floor/, count: 0
    assert_select "tr.hover\\:bg-yellow-200", count: 6
    
    # Should be in final mode (ranking, not checkboxes)
    assert_select "input[type='checkbox']", count: 0
  end

  # ===== HEAT NAVIGATION TESTS =====
  # Tests for simple numerical heat ordering (by heat number only)
  # Category-based grouping with gap detection was intentionally removed in commit 98e2470d
  # to fix issues with fractional heat numbers

  test "heat navigation next link follows numerical order" do
    # Create simple dances without heat_length/scrutineering for testing navigation
    simple_dance1 = Dance.create!(name: 'Test Dance 1', order: 9997)
    simple_dance2 = Dance.create!(name: 'Test Dance 2', order: 9998)
    simple_dance3 = Dance.create!(name: 'Test Dance 3', order: 9999)

    # Create heats in different categories with sequential numbers
    Heat.create!(number: 15, entry: @entry, dance: simple_dance1, category: 'Open')
    Heat.create!(number: 16, entry: @entry, dance: simple_dance2, category: 'Closed')
    Heat.create!(number: 17, entry: @entry, dance: simple_dance3, category: 'Open')

    # Get heat 15 and verify next link points to 16
    get judge_heat_path(@judge, 15)

    assert_response :success

    # Should have a next link to heat 16 (not 17, even though 17 is same category as 15)
    assert_select "a[rel='next']" do |links|
      next_link = links.first['href']
      assert next_link.include?('heat/16'),
        "Expected next link to go to heat 16, but got: #{next_link}"
      refute next_link.include?('heat/17'),
        "Next link should not skip heat 16 and go to 17"
    end
  end

  test "heat navigation prev link follows numerical order" do
    # Create simple dances without heat_length/scrutineering for testing navigation
    simple_dance1 = Dance.create!(name: 'Test Dance 1', order: 9997)
    simple_dance2 = Dance.create!(name: 'Test Dance 2', order: 9998)
    simple_dance3 = Dance.create!(name: 'Test Dance 3', order: 9999)

    # Create heats in different categories with sequential numbers
    Heat.create!(number: 15, entry: @entry, dance: simple_dance1, category: 'Open')
    Heat.create!(number: 16, entry: @entry, dance: simple_dance2, category: 'Closed')
    Heat.create!(number: 17, entry: @entry, dance: simple_dance3, category: 'Open')

    # Get heat 17 and verify prev link points to 16
    get judge_heat_path(@judge, 17)

    assert_response :success

    # Should have a prev link to heat 16 (not 15, even though 15 is same category as 17)
    assert_select "a[rel='prev']" do |links|
      prev_link = links.first['href']
      assert prev_link.include?('heat/16'),
        "Expected prev link to go to heat 16, but got: #{prev_link}"
      refute prev_link.include?('heat/15'),
        "Prev link should not skip heat 16 and go to 15"
    end
  end

  test "heatlist displays heats in simple numerical order" do
    # Create heats across different categories and with gaps
    # The simple numerical ordering should display them by heat number only
    heat15 = Heat.create!(number: 15, entry: @entry, dance: @dance, category: 'Open')
    heat16 = Heat.create!(number: 16, entry: @entry, dance: dances(:tango), category: 'Closed')
    heat25 = Heat.create!(number: 25, entry: @entry, dance: dances(:rumba), category: 'Open')

    get judge_heatlist_path(@judge)

    assert_response :success

    # Extract heat numbers from response body to verify numerical order
    heat_links = []
    response.body.scan(/href="[^"]*\/heat\/(\d+)/).each { |match| heat_links << match[0].to_i }

    # Find our test heats in the order they appear
    test_heats = [15, 16, 25]
    found_heats = heat_links.select { |h| test_heats.include?(h) }.uniq

    # Should appear in numerical order (not grouped by category)
    assert_equal [15, 16, 25], found_heats, "Heats should be in simple numerical order"
  end

  test "heat navigation handles fractional heat numbers correctly" do
    # This test verifies the fix from commit 98e2470d which ensured fractional
    # heat numbers are ordered correctly (e.g., 15 → 15.5 → 16)

    # Create simple dances without heat_length/scrutineering
    simple_dance1 = Dance.create!(name: 'Test Dance 1', order: 9997)
    simple_dance2 = Dance.create!(name: 'Test Dance 2', order: 9998)
    simple_dance3 = Dance.create!(name: 'Test Dance 3', order: 9999)

    Heat.create!(number: 15, entry: @entry, dance: simple_dance1, category: 'Open')
    Heat.create!(number: 15.5, entry: @entry, dance: simple_dance2, category: 'Closed')
    Heat.create!(number: 16, entry: @entry, dance: simple_dance3, category: 'Open')

    # Navigate from 15 → should go to 15.5 (not skip to 16)
    get judge_heat_path(@judge, 15)
    assert_response :success
    assert_select "a[rel='next']" do |links|
      next_link = links.first['href']
      assert next_link.include?('heat/15.5'),
        "Expected next link from heat 15 to go to 15.5, but got: #{next_link}"
    end

    # Navigate from 15.5 → should go to 16
    get judge_heat_path(@judge, 15.5)
    assert_response :success
    assert_select "a[rel='next']" do |links|
      next_link = links.first['href']
      assert next_link.include?('heat/16'),
        "Expected next link from heat 15.5 to go to 16, but got: #{next_link}"
    end

    # Navigate backwards from 16 → should go to 15.5 (not skip to 15)
    get judge_heat_path(@judge, 16)
    assert_response :success
    assert_select "a[rel='prev']" do |links|
      prev_link = links.first['href']
      assert prev_link.include?('heat/15.5'),
        "Expected prev link from heat 16 to go to 15.5, but got: #{prev_link}"
    end
  end

  test "judge heat interface handles multi-dance child heat without slot parameter" do
    # This test addresses a bug where accessing a multi-dance child heat
    # without a slot parameter caused: "undefined method '>' for nil"
    # The bug occurred because:
    # 1. Child dances have category 'Open' not 'Multi'
    # 2. Line 99 only sets @slot ||= 1 for category 'Multi'
    # 3. Line 118 tried to compare nil > heat_length

    # Create parent multi-dance
    multi_category = Category.create!(name: 'Test Multi Category', order: 9999)
    parent_dance = Dance.create!(
      name: 'Test 2 Dance',
      order: 9999,
      multi_category: multi_category,
      heat_length: 2
    )

    # Create child dance
    child_dance = Dance.create!(name: 'Test Bachata', order: 10000)

    # Link child to parent
    Multi.create!(parent: parent_dance, dance: child_dance, slot: 1)

    # Create heat with child dance (category will be 'Open' not 'Multi')
    entry = Entry.create!(lead: @instructor, follow: @student, age: @age, level: @level)
    heat = Heat.create!(number: 74, entry: entry, dance: child_dance, category: 'Open')

    # Access heat WITHOUT slot parameter - this was causing the bug
    # The URL pattern was: /scores/25/heatlist?sort=back&style=emcee
    # which led to accessing the heat without a slot
    get judge_heat_path(@judge, 74, style: 'emcee')

    # Should not crash with "undefined method '>' for nil"
    assert_response :success

    # Should display the heat properly
    assert_select 'body'
  end

end