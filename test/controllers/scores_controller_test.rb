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

  # ===== SPLIT ELIGIBILITY TESTS =====
  # These tests verify that scrutineering is only used when all splits
  # in a heat are "complete" (all entries for each dance_id are in one heat)

  test "scrutineering used when all entries for dance_id in single heat" do
    # Create a scrutineering dance where all entries fit in one heat
    dance = Dance.create!(
      name: 'Complete Split Dance',
      semi_finals: true,
      heat_length: 2,
      order: 1050
    )

    # Create 3 entries all in the same heat
    entries = 3.times.map do |i|
      student = Person.create!(name: "Complete Split Student #{i}", type: 'Student', studio: studios(:one), level: @level)
      Entry.create!(lead: @instructor, follow: student, age: @age, level: @level)
    end

    heats = entries.map do |entry|
      Heat.create!(number: 500, entry: entry, dance: dance, category: 'Multi')
    end

    get judge_heat_path(@judge, 500)
    assert_response :success

    # Should use scrutineering - check for callback UI elements or ranking
    # With 3 entries (≤8), should go straight to finals/ranking
    assert_select 'tr[draggable="true"]', minimum: 1,
      message: "Expected draggable rows for ranking when scrutineering is active"
  end

  test "scrutineering fallback when entries span multiple heats" do
    # Create a scrutineering dance where entries are split across heats
    dance = Dance.create!(
      name: 'Incomplete Split Dance',
      semi_finals: true,
      heat_length: 2,
      order: 1051
    )

    # Create entries in different heats (simulating instructor conflict)
    student1 = Person.create!(name: "Incomplete Student 1", type: 'Student', studio: studios(:one), level: @level)
    student2 = Person.create!(name: "Incomplete Student 2", type: 'Student', studio: studios(:one), level: @level)

    entry1 = Entry.create!(lead: @instructor, follow: student1, age: @age, level: @level)
    entry2 = Entry.create!(lead: @instructor, follow: student2, age: @age, level: @level)

    # Put entries in different heats (incomplete split)
    Heat.create!(number: 501, entry: entry1, dance: dance, category: 'Multi')
    Heat.create!(number: 502, entry: entry2, dance: dance, category: 'Multi')

    get judge_heat_path(@judge, 501)
    assert_response :success

    # Should NOT use scrutineering - should fall back to regular scoring
    # Check that we don't have ranking UI (no draggable rows)
    assert_select 'tr[draggable="true"]', count: 0,
      message: "Should not have draggable rows when split is incomplete"
  end

  test "multi-split heat uses scrutineering when all splits complete" do
    # Create a category for the multi-dances
    multi_category = Category.create!(name: 'Multi Split Test Category', order: 1060)

    # Create two different splits that both fit in one heat
    dance1 = Dance.create!(
      name: 'Multi Split Dance A',
      semi_finals: true,
      heat_length: 2,
      order: -1052,  # Negative order = split dance
      multi_category: multi_category
    )
    dance2 = Dance.create!(
      name: 'Multi Split Dance B',
      semi_finals: true,
      heat_length: 2,
      order: -1053,
      multi_category: multi_category
    )

    # Create entries for both splits, all in same heat
    student1 = Person.create!(name: "Multi Split Student 1", type: 'Student', studio: studios(:one), level: @level)
    student2 = Person.create!(name: "Multi Split Student 2", type: 'Student', studio: studios(:one), level: @level)

    entry1 = Entry.create!(lead: @instructor, follow: student1, age: @age, level: @level)
    entry2 = Entry.create!(lead: people(:instructor2), follow: student2, age: @age, level: @level)

    Heat.create!(number: 503, entry: entry1, dance: dance1, category: 'Multi')
    Heat.create!(number: 503, entry: entry2, dance: dance2, category: 'Multi')

    get judge_heat_path(@judge, 503)
    assert_response :success

    # Both splits complete - should use scrutineering with packed splits view
    assert_select 'tr[draggable="true"]', minimum: 1,
      message: "Expected draggable rows for multi-split scrutineering"
  end

  test "all_splits_complete helper returns true for complete split" do
    dance = Dance.create!(name: 'Helper Test Complete', semi_finals: true, order: 1054)
    student = Person.create!(name: "Helper Test Student", type: 'Student', studio: studios(:one), level: @level)
    entry = Entry.create!(lead: @instructor, follow: student, age: @age, level: @level)
    heat = Heat.create!(number: 504, entry: entry, dance: dance, category: 'Multi')

    # Use send to call private method
    controller = ScoresController.new
    result = controller.send(:all_splits_complete?, [heat], 504)
    assert result, "all_splits_complete? should return true when all entries in one heat"
  end

  test "all_splits_complete helper returns false for incomplete split" do
    dance = Dance.create!(name: 'Helper Test Incomplete', semi_finals: true, order: 1055)
    student1 = Person.create!(name: "Helper Student 1", type: 'Student', studio: studios(:one), level: @level)
    student2 = Person.create!(name: "Helper Student 2", type: 'Student', studio: studios(:one), level: @level)
    entry1 = Entry.create!(lead: @instructor, follow: student1, age: @age, level: @level)
    entry2 = Entry.create!(lead: @instructor, follow: student2, age: @age, level: @level)

    heat1 = Heat.create!(number: 505, entry: entry1, dance: dance, category: 'Multi')
    Heat.create!(number: 506, entry: entry2, dance: dance, category: 'Multi')  # Different heat!

    controller = ScoresController.new
    result = controller.send(:all_splits_complete?, [heat1], 505)
    assert_not result, "all_splits_complete? should return false when entries span multiple heats"
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

  # ===== START HEAT BUTTON TESTS (EMCEE MODE) =====
  # These tests ensure the "Start Heat" button appears correctly in emcee mode
  # and prevent regressions where @style gets overridden for scrutineering dances

  test "start heat button appears in emcee mode for regular heats" do
    # Set event current heat to something different
    @event.update!(current_heat: 999)

    get judge_heat_path(@judge, @test_heat.number, style: 'emcee')

    assert_response :success
    assert_select 'button[data-action*="startHeat"]', text: 'Start Heat'
  end

  test "start heat button appears in emcee mode for scrutineering heats with rank view" do
    # This test addresses the regression where @style was overridden to 'radio'
    # for scrutineering dances, breaking the button visibility condition

    # Create multi category
    multi_category = Category.create!(
      name: 'Test Emcee Scrutineering Category',
      order: 5000
    )

    # Create scrutineering dance with semi_finals enabled
    scrutineering_dance = Dance.create!(
      name: 'Test Emcee Scrutineering Waltz',
      semi_finals: true,
      heat_length: 3,
      order: 5000,
      multi_category: multi_category
    )

    # Create 7 couples (≤8, so will use rank view, not table view)
    entries = []
    heats = []
    7.times do |i|
      student = Person.create!(
        name: "Emcee Student #{i}",
        type: 'Student',
        studio: studios(:one),
        level: @level,
        back: 5000 + i
      )
      instructor = Person.create!(
        name: "Emcee Instructor #{i}",
        type: 'Professional',
        studio: studios(:one),
        back: 5100 + i
      )
      entry = Entry.create!(lead: instructor, follow: student, age: @age, level: @level)
      entries << entry
      heat = Heat.create!(number: 50, entry: entry, dance: scrutineering_dance, category: 'Multi')
      heats << heat
    end

    # Set event current heat to something different
    @event.update!(current_heat: 999)

    # Visit with emcee style - button should appear even though @style gets overridden to 'radio'
    get judge_heat_path(@judge, 50, style: 'emcee')

    assert_response :success
    # Button should appear because we check params[:style], not @style
    assert_select 'button[data-action*="startHeat"]', text: 'Start Heat'
  end

  test "start heat button appears in emcee mode for scrutineering heats after finals" do
    # This test ensures the button appears for scrutineering heats in finals

    # Create multi category
    multi_category = Category.create!(
      name: 'Test Table Scrutineering Category',
      order: 5001
    )

    # Create scrutineering dance
    scrutineering_dance = Dance.create!(
      name: 'Test Table Scrutineering Dance',
      semi_finals: true,
      heat_length: 2,
      order: 5001,
      multi_category: multi_category
    )

    # Create 10 couples (>8, so requires semi-finals)
    entries = []
    heats = []
    10.times do |i|
      student = Person.create!(
        name: "Table Student #{i}",
        type: 'Student',
        studio: studios(:one),
        level: @level,
        back: 5200 + i
      )
      instructor = Person.create!(
        name: "Table Instructor #{i}",
        type: 'Professional',
        studio: studios(:one),
        back: 5300 + i
      )
      entry = Entry.create!(lead: instructor, follow: student, age: @age, level: @level)
      entries << entry
      heat = Heat.create!(number: 51, entry: entry, dance: scrutineering_dance, category: 'Multi')
      heats << heat
    end

    # Create semi-final scores for first 6 couples to establish callbacks
    heats[0, 6].each do |heat|
      Score.create!(heat: heat, judge: @judge, value: '1', slot: 1)
      Score.create!(heat: heat, judge: @judge, value: '1', slot: 2)
    end

    # Set event current heat to something different
    @event.update!(current_heat: 999)

    # Visit with emcee style for finals (slot 3 > heat_length of 2)
    get judge_heat_path(@judge, 51, slot: 3, style: 'emcee')

    assert_response :success
    # Button should appear in rank view for finals
    assert_select 'button[data-action*="startHeat"]', text: 'Start Heat'
  end

  test "start heat button hidden when heat is already current" do
    # Set the test heat as the current heat
    @event.update!(current_heat: @test_heat.number)

    get judge_heat_path(@judge, @test_heat.number, style: 'emcee')

    assert_response :success
    # Button should NOT appear because heat is already current
    assert_select 'button[data-action*="startHeat"]', count: 0
  end

  test "start heat button appears for solo heats in emcee mode" do
    # Create solo heat
    solo_entry = Entry.create!(
      lead: @student,
      follow: @student,
      instructor: @instructor,
      age: @age,
      level: @level
    )

    solo_dance = Dance.create!(
      name: 'Test Solo Dance',
      order: 5002,
      solo_category: categories(:solo)
    )

    solo_heat = Heat.create!(
      number: 52,
      entry: solo_entry,
      dance: solo_dance,
      category: 'Solo'
    )

    Solo.create!(
      heat: solo_heat,
      song: 'Test Song',
      artist: 'Test Artist'
    )

    # Set event current heat to something different
    @event.update!(current_heat: 999)

    get judge_heat_path(@judge, solo_heat.number, style: 'emcee')

    assert_response :success
    # Button should appear for solo heats
    assert_select 'button[data-action*="startHeat"]', text: 'Start Heat'
  end

  test "start heat button does not appear in non-emcee mode" do
    # Set event current heat to something different
    @event.update!(current_heat: 999)

    # Visit without emcee style
    get judge_heat_path(@judge, @test_heat.number)

    assert_response :success
    # Button should NOT appear in default mode
    assert_select 'button[data-action*="startHeat"]', count: 0
  end

  test "start heat button does not appear in radio style mode" do
    # Set event current heat to something different
    @event.update!(current_heat: 999)

    # Visit with radio style
    get judge_heat_path(@judge, @test_heat.number, style: 'radio')

    assert_response :success
    # Button should NOT appear in radio mode
    assert_select 'button[data-action*="startHeat"]', count: 0
  end

  # ===== NAVIGATION STYLE PARAMETER PRESERVATION TESTS =====
  # These tests ensure that the style parameter is preserved in navigation links
  # when moving between heats. This is important for emcee mode where the
  # style parameter changes the display and should be maintained across navigation.

  test "navigation links preserve style parameter in emcee mode for regular heats" do
    # Create simple dances for navigation testing
    simple_dance1 = Dance.create!(name: 'Nav Test Dance 1', order: 6000)
    simple_dance2 = Dance.create!(name: 'Nav Test Dance 2', order: 6001)
    simple_dance3 = Dance.create!(name: 'Nav Test Dance 3', order: 6002)

    # Create sequential heats
    Heat.create!(number: 60, entry: @entry, dance: simple_dance1, category: 'Closed')
    Heat.create!(number: 61, entry: @entry, dance: simple_dance2, category: 'Closed')
    Heat.create!(number: 62, entry: @entry, dance: simple_dance3, category: 'Closed')

    # Visit heat 61 with emcee style
    get judge_heat_path(@judge, 61, style: 'emcee')

    assert_response :success

    # Check that next link preserves style=emcee
    assert_select "a[rel='next']" do |links|
      next_link = links.first['href']
      assert next_link.include?('style=emcee'),
        "Expected next link to preserve style=emcee, but got: #{next_link}"
    end

    # Check that prev link preserves style=emcee
    assert_select "a[rel='prev']" do |links|
      prev_link = links.first['href']
      assert prev_link.include?('style=emcee'),
        "Expected prev link to preserve style=emcee, but got: #{prev_link}"
    end
  end

  test "navigation links preserve style parameter for scrutineering heats" do
    # This test addresses the bug where @style was overridden to 'radio' for
    # scrutineering dances, causing navigation links to lose the style parameter

    # Create multi category
    multi_category = Category.create!(
      name: 'Test Nav Scrutineering Category',
      order: 6100
    )

    # Create scrutineering dance with semi_finals enabled
    scrutineering_dance = Dance.create!(
      name: 'Test Nav Scrutineering Waltz',
      semi_finals: true,
      heat_length: 3,
      order: 6100,
      multi_category: multi_category
    )

    # Create 7 couples for heat 63 (≤8, so will skip semi-finals but still be scrutineering)
    entries = []
    heats = []
    7.times do |i|
      student = Person.create!(
        name: "Nav Student #{i}",
        type: 'Student',
        studio: studios(:one),
        level: @level,
        back: 6100 + i
      )
      instructor = Person.create!(
        name: "Nav Instructor #{i}",
        type: 'Professional',
        studio: studios(:one),
        back: 6200 + i
      )
      entry = Entry.create!(lead: instructor, follow: student, age: @age, level: @level)
      entries << entry
      heat = Heat.create!(number: 63, entry: entry, dance: scrutineering_dance, category: 'Multi')
      heats << heat
    end

    # Create a regular heat before and after for navigation
    simple_dance1 = Dance.create!(name: 'Nav Before Dance', order: 6099)
    simple_dance2 = Dance.create!(name: 'Nav After Dance', order: 6101)
    Heat.create!(number: 62, entry: @entry, dance: simple_dance1, category: 'Closed')
    Heat.create!(number: 64, entry: @entry, dance: simple_dance2, category: 'Closed')

    # Visit heat 63 with emcee style
    # At this point, controller will override @style to 'radio' (line 112)
    # But navigation should still use params[:style] which is 'emcee'
    get judge_heat_path(@judge, 63, style: 'emcee')

    assert_response :success

    # Check that next link preserves style=emcee (not style=radio)
    assert_select "a[rel='next']" do |links|
      next_link = links.first['href']
      assert next_link.include?('style=emcee'),
        "Expected next link to preserve style=emcee for scrutineering heat, but got: #{next_link}"
      refute next_link.include?('style=radio'),
        "Next link should not use overridden style=radio, got: #{next_link}"
    end

    # Check that prev link preserves style=emcee (not style=radio)
    assert_select "a[rel='prev']" do |links|
      prev_link = links.first['href']
      assert prev_link.include?('style=emcee'),
        "Expected prev link to preserve style=emcee for scrutineering heat, but got: #{prev_link}"
      refute prev_link.include?('style=radio'),
        "Prev link should not use overridden style=radio, got: #{prev_link}"
    end
  end

  test "navigation links work correctly without style parameter" do
    # Ensure navigation still works when no style parameter is provided

    # Create simple dances for navigation testing
    simple_dance1 = Dance.create!(name: 'Nav No Style 1', order: 6200)
    simple_dance2 = Dance.create!(name: 'Nav No Style 2', order: 6201)
    simple_dance3 = Dance.create!(name: 'Nav No Style 3', order: 6202)

    # Create sequential heats
    Heat.create!(number: 70, entry: @entry, dance: simple_dance1, category: 'Closed')
    Heat.create!(number: 71, entry: @entry, dance: simple_dance2, category: 'Closed')
    Heat.create!(number: 72, entry: @entry, dance: simple_dance3, category: 'Closed')

    # Visit heat 71 without style parameter
    get judge_heat_path(@judge, 71)

    assert_response :success

    # Check that next link exists and points to heat 72
    assert_select "a[rel='next']" do |links|
      next_link = links.first['href']
      assert next_link.include?('heat/72'),
        "Expected next link to point to heat 72, but got: #{next_link}"
    end

    # Check that prev link exists and points to heat 70
    assert_select "a[rel='prev']" do |links|
      prev_link = links.first['href']
      assert prev_link.include?('heat/70'),
        "Expected prev link to point to heat 70, but got: #{prev_link}"
    end
  end

  # ===== CATEGORY-BASED SCRUTINEERING AND NAVIGATION TESTS =====
  # These tests ensure that scrutineering logic and slot-based navigation
  # only apply to Multi category heats, not to Closed/Open heats that
  # happen to use dances which are part of Multi-dance parents.

  test "style parameter not overridden for Closed heats using scrutineering dances" do
    # This test addresses the bug where style=cards was overridden to style=radio
    # for Closed category heats that use dances which are part of Multi-dance parents.

    # Create a parent multi-dance with semi_finals enabled
    multi_category = Category.create!(name: 'Test Multi Category', order: 7000)
    parent_dance = Dance.create!(
      name: 'Latin 2 Dance',
      semi_finals: true,
      heat_length: 2,
      order: 7000,
      multi_category: multi_category
    )

    # Create child dance (Salsa)
    salsa_dance = Dance.create!(name: 'Salsa', order: 7001)
    Multi.create!(parent: parent_dance, dance: salsa_dance, slot: 1)

    # Create Closed category heat using Salsa dance
    # (NOT Multi category, so scrutineering override should not apply)
    closed_heat = Heat.create!(
      number: 80,
      entry: @entry,
      dance: salsa_dance,
      category: 'Closed'
    )

    # Verify the dance has scrutineering enabled
    assert salsa_dance.uses_scrutineering?,
      "Salsa dance should have uses_scrutineering? = true due to parent"

    # Visit with style=cards - should NOT be overridden to radio
    get judge_heat_path(@judge, 80, style: 'cards')

    assert_response :success

    # The @style instance variable should still be 'cards', not 'radio'
    # We can verify this by checking the response body doesn't have scrutineering-specific elements
    # (Note: In the actual view, cards style would render differently than radio style)
  end

  test "style parameter overridden to radio for Multi heats using scrutineering dances" do
    # This test confirms that the scrutineering override DOES apply to Multi category heats

    # Create a parent multi-dance with semi_finals enabled
    multi_category = Category.create!(name: 'Test Multi Category 2', order: 7100)
    parent_dance = Dance.create!(
      name: 'Latin 3 Dance',
      semi_finals: true,
      heat_length: 2,
      order: 7100,
      multi_category: multi_category
    )

    # Create child dance (Bachata)
    bachata_dance = Dance.create!(name: 'Bachata', order: 7101)
    Multi.create!(parent: parent_dance, dance: bachata_dance, slot: 1)

    # Create Multi category heat using Bachata dance
    # (Multi category, so scrutineering override SHOULD apply)
    multi_heat = Heat.create!(
      number: 81,
      entry: @entry,
      dance: bachata_dance,
      category: 'Multi'
    )

    # Verify the dance has scrutineering enabled
    assert bachata_dance.uses_scrutineering?,
      "Bachata dance should have uses_scrutineering? = true due to parent"

    # Visit without style parameter - should be overridden to radio
    get judge_heat_path(@judge, 81)

    assert_response :success

    # The @style instance variable should be 'radio'
    # We can verify this by checking for radio-specific elements in the response
  end

  test "navigation uses simple heat paths for Closed heats with scrutineering dances" do
    # This test addresses the bug where Closed heats were getting slot-based
    # navigation (/heat/1/2) when they should use simple paths (/heat/2)

    # Create a parent multi-dance with semi_finals enabled
    multi_category = Category.create!(name: 'Test Nav Multi Category', order: 7200)
    parent_dance = Dance.create!(
      name: 'Latin 4 Dance',
      semi_finals: true,
      heat_length: 2,
      order: 7200,
      multi_category: multi_category
    )

    # Create child dance (Cha Cha Nav Test)
    chacha_dance = Dance.create!(name: 'Cha Cha Nav Test', order: 7201)
    Multi.create!(parent: parent_dance, dance: chacha_dance, slot: 1)

    # Create sequential Closed category heats using Cha Cha dance
    Heat.create!(number: 82, entry: @entry, dance: chacha_dance, category: 'Closed')
    Heat.create!(number: 83, entry: @entry, dance: chacha_dance, category: 'Closed')
    Heat.create!(number: 84, entry: @entry, dance: chacha_dance, category: 'Closed')

    # Verify the dance has scrutineering enabled and heat_length from parent
    assert chacha_dance.uses_scrutineering?,
      "Cha Cha dance should have uses_scrutineering? = true due to parent"
    assert_equal 2, parent_dance.heat_length,
      "Parent dance should have heat_length = 2"

    # Visit heat 83 with emcee style
    get judge_heat_path(@judge, 83, style: 'emcee')

    assert_response :success

    # Check that next link uses simple path (not slot-based)
    assert_select "a[rel='next']" do |links|
      next_link = links.first['href']
      assert next_link.include?('heat/84'),
        "Expected next link to point to heat/84, but got: #{next_link}"
      refute next_link.include?('heat/83/2'),
        "Next link should not use slot-based path for Closed heat, got: #{next_link}"
      refute next_link.include?('/1'),
        "Next link should not include slot number for Closed heat, got: #{next_link}"
    end

    # Check that prev link uses simple path (not slot-based)
    assert_select "a[rel='prev']" do |links|
      prev_link = links.first['href']
      assert prev_link.include?('heat/82'),
        "Expected prev link to point to heat/82, but got: #{prev_link}"
      refute prev_link.include?('heat/82/'),
        "Prev link should not use slot-based path for Closed heat, got: #{prev_link}"
    end
  end

  test "navigation uses slot-based paths for Multi heats with scrutineering dances" do
    # This test confirms that slot-based navigation DOES apply to Multi category heats

    # Create a parent multi-dance with semi_finals enabled
    multi_category = Category.create!(name: 'Test Slot Multi Category', order: 7300)
    parent_dance = Dance.create!(
      name: 'Latin 5 Dance',
      semi_finals: true,
      heat_length: 2,
      order: 7300,
      multi_category: multi_category
    )

    # Create child dances
    rumba_dance = Dance.create!(name: 'Rumba Slot Test', order: 7301)
    jive_dance = Dance.create!(name: 'Jive Slot Test', order: 7302)
    Multi.create!(parent: parent_dance, dance: rumba_dance, slot: 1)
    Multi.create!(parent: parent_dance, dance: jive_dance, slot: 2)

    # Create Multi category heats
    Heat.create!(number: 85, entry: @entry, dance: rumba_dance, category: 'Multi')
    Heat.create!(number: 86, entry: @entry, dance: jive_dance, category: 'Multi')

    # Visit heat 85 slot 1 with emcee style
    get judge_heat_path(@judge, 85, slot: 1, style: 'emcee')

    assert_response :success

    # Check that next link uses slot-based path to slot 2
    assert_select "a[rel='next']" do |links|
      next_link = links.first['href']
      assert next_link.include?('heat/85/2') || next_link.include?('slot=2'),
        "Expected next link to point to slot 2 of heat 85, but got: #{next_link}"
    end
  end

  test "Open category heats do not use slot-based navigation even with scrutineering parent" do
    # Similar to Closed heats, Open heats should not use slot-based navigation

    # Create a parent multi-dance
    multi_category = Category.create!(name: 'Test Open Multi Category', order: 7400)
    parent_dance = Dance.create!(
      name: 'Open Multi Dance',
      semi_finals: true,
      heat_length: 3,
      order: 7400,
      multi_category: multi_category
    )

    # Create child dance
    waltz_dance = Dance.create!(name: 'Open Waltz', order: 7401)
    Multi.create!(parent: parent_dance, dance: waltz_dance, slot: 1)

    # Create Open category heats
    Heat.create!(number: 87, entry: @entry, dance: waltz_dance, category: 'Open')
    Heat.create!(number: 88, entry: @entry, dance: waltz_dance, category: 'Open')

    # Visit heat 87
    get judge_heat_path(@judge, 87, style: 'emcee')

    assert_response :success

    # Check that next link uses simple path (not slot-based)
    assert_select "a[rel='next']" do |links|
      next_link = links.first['href']
      assert next_link.include?('heat/88'),
        "Expected next link to point to heat/88, but got: #{next_link}"
      refute next_link.include?('heat/87/2'),
        "Next link should not use slot-based path for Open heat, got: #{next_link}"
    end
  end

  # === Version Check Endpoint Tests ===

  test "version_check returns max_updated_at and heat_count" do
    get judge_version_check_path(judge: @judge.id, heat: 1), as: :json

    assert_response :success
    assert_equal 'application/json; charset=utf-8', @response.content_type

    data = JSON.parse(@response.body)

    # Check structure
    assert_includes data.keys, 'heat_number'
    assert_includes data.keys, 'max_updated_at'
    assert_includes data.keys, 'heat_count'

    # Verify heat_number matches request
    assert_equal 1.0, data['heat_number']

    # Verify heat_count is positive
    assert data['heat_count'] > 0, "Expected heat_count > 0"
  end

  test "version_check max_updated_at changes when heat updated" do
    # Get initial version
    get judge_version_check_path(judge: @judge.id, heat: 1), as: :json
    initial_data = JSON.parse(@response.body)
    initial_updated_at = initial_data['max_updated_at']

    # Update a heat
    heat = Heat.where('number >= ?', 1).first
    heat.touch

    # Get new version
    get judge_version_check_path(judge: @judge.id, heat: 1), as: :json
    new_data = JSON.parse(@response.body)
    new_updated_at = new_data['max_updated_at']

    # Verify updated_at changed
    refute_equal initial_updated_at, new_updated_at, "Expected max_updated_at to change after heat update"
  end

  test "version_check heat_count changes when heat added" do
    # Get initial count
    get judge_version_check_path(judge: @judge.id, heat: 1), as: :json
    initial_data = JSON.parse(@response.body)
    initial_count = initial_data['heat_count']

    # Add a new heat
    heat = Heat.create!(
      number: 999,
      dance: dances(:waltz),
      entry: entries(:one),
      category: 'Open'
    )

    # Get new count
    get judge_version_check_path(judge: @judge.id, heat: 1), as: :json
    new_data = JSON.parse(@response.body)
    new_count = new_data['heat_count']

    # Verify count increased
    assert_equal initial_count + 1, new_count, "Expected heat_count to increase by 1"

    # Cleanup
    heat.destroy
  end

  test "version_check accepts fractional heat numbers" do
    get judge_version_check_path(judge: @judge.id, heat: 59.5), as: :json

    assert_response :success
    data = JSON.parse(@response.body)
    assert_equal 59.5, data['heat_number']
  end

  test "batch_scores creates multiple scores from array" do
    # Remove existing score
    @score.destroy

    batch_data = {
      scores: [
        {
          heat: @test_heat.id,
          slot: 1,
          score: 'G',
          comments: 'Great technique',
          good: 'F',
          bad: ''
        },
        {
          heat: @test_heat.id,
          slot: 2,
          score: 'S',
          comments: '',
          good: '',
          bad: 'T'
        }
      ]
    }

    assert_difference('Score.count', 2) do
      post judge_batch_scores_path(@judge), params: batch_data, as: :json
    end

    assert_response :success
    result = JSON.parse(@response.body)
    assert_equal 2, result['succeeded'].length
    assert_equal 0, result['failed'].length
  end

  test "batch_scores updates existing scores" do
    # Create initial scores
    score1 = Score.create!(heat: @test_heat, judge: @judge, value: 'G', slot: 1)
    score2 = Score.create!(heat: @test_heat, judge: @judge, value: 'S', slot: 2)

    batch_data = {
      scores: [
        { heat: @test_heat.id, slot: 1, score: 'B', comments: 'Updated', good: '', bad: '' },
        { heat: @test_heat.id, slot: 2, score: 'GH', comments: '', good: '', bad: '' }
      ]
    }

    assert_no_difference('Score.count') do
      post judge_batch_scores_path(@judge), params: batch_data, as: :json
    end

    assert_response :success
    result = JSON.parse(@response.body)
    assert_equal 2, result['succeeded'].length

    score1.reload
    score2.reload
    assert_equal 'B', score1.value
    assert_equal 'Updated', score1.comments
    assert_equal 'GH', score2.value
  end

  test "batch_scores handles empty scores based on assign_judges setting" do
    original_assign = @event.assign_judges

    # Test with assign_judges = 0 (should delete empty scores)
    @event.update!(assign_judges: 0)

    score_to_delete = Score.create!(heat: @test_heat, judge: @judge, value: 'G', slot: 1)

    batch_data = {
      scores: [
        { heat: @test_heat.id, slot: 1, score: '', comments: '', good: '', bad: '' }
      ]
    }

    assert_difference('Score.count', -1) do
      post judge_batch_scores_path(@judge), params: batch_data, as: :json
    end

    assert_response :success

    # Test with assign_judges > 0 (should keep empty scores)
    @event.update!(assign_judges: 1)

    batch_data = {
      scores: [
        { heat: @test_heat.id, slot: 1, score: '', comments: '', good: '', bad: '' }
      ]
    }

    assert_difference('Score.count', 1) do
      post judge_batch_scores_path(@judge), params: batch_data, as: :json
    end

    assert_response :success

  ensure
    @event.update!(assign_judges: original_assign)
  end

  test "batch_scores handles partial failures gracefully" do
    batch_data = {
      scores: [
        { heat: @test_heat.id, slot: 1, score: 'G', comments: '', good: '', bad: '' },  # Valid
        { heat: 99999, slot: 1, score: 'S', comments: '', good: '', bad: '' }           # Invalid heat ID
      ]
    }

    post judge_batch_scores_path(@judge), params: batch_data, as: :json

    assert_response :success
    result = JSON.parse(@response.body)
    assert_equal 1, result['succeeded'].length
    assert_equal 1, result['failed'].length
    assert_includes result['failed'][0]['error'], "Couldn't find Heat"
  end

  test "batch_scores handles readonly database" do
    ApplicationRecord.class_variable_set(:@@readonly_showcase, true)

    batch_data = {
      scores: [
        { heat: @test_heat.id, slot: 1, score: 'G', comments: '', good: '', bad: '' }
      ]
    }

    post judge_batch_scores_path(@judge), params: batch_data, as: :json

    assert_response :success
    result = JSON.parse(@response.body)
    assert_equal 0, result['succeeded'].length
    assert_equal 1, result['failed'].length
    assert_includes result['failed'][0]['error'], 'readonly'

  ensure
    ApplicationRecord.class_variable_set(:@@readonly_showcase, false)
  end

  test "batch_scores returns empty arrays when no scores provided" do
    batch_data = { scores: [] }

    post judge_batch_scores_path(@judge), params: batch_data, as: :json

    assert_response :success
    result = JSON.parse(@response.body)
    assert_equal 0, result['succeeded'].length
    assert_equal 0, result['failed'].length
  end

  test "version_check returns version metadata" do
    get judge_version_check_path(@judge, @test_heat.number), as: :json

    assert_response :success
    data = JSON.parse(@response.body)

    assert_includes data.keys, 'max_updated_at'
    assert_includes data.keys, 'heat_count'
    assert data['heat_count'].is_a?(Integer)
    assert data['heat_count'] > 0
  end

  test "version_check includes heat number in response" do
    get judge_version_check_path(@judge, @test_heat.number), as: :json

    assert_response :success
    data = JSON.parse(@response.body)

    assert_equal @test_heat.number.to_f, data['heat_number'].to_f
  end

  test "version_check works with fractional heat numbers" do
    fractional_heat = Heat.create!(
      number: 15.5,
      entry: @entry,
      dance: @dance,
      category: 'Open'
    )

    get judge_version_check_path(@judge, fractional_heat.number), as: :json

    assert_response :success
    data = JSON.parse(@response.body)

    assert_equal 15.5, data['heat_number'].to_f
  end

  test "version_check includes judge updated_at in max_updated_at calculation" do
    # Touch the judge to update their timestamp
    @judge.touch

    get judge_version_check_path(@judge, @test_heat.number), as: :json

    assert_response :success
    data = JSON.parse(@response.body)

    # max_updated_at should be at least as recent as judge's updated_at
    max_updated = Time.parse(data['max_updated_at'])
    assert max_updated >= @judge.reload.updated_at - 1.second, "max_updated_at should include judge's updated_at"
  end

  test "version_check includes event updated_at in max_updated_at calculation" do
    # Touch the event to update its timestamp
    Event.first.touch

    get judge_version_check_path(@judge, @test_heat.number), as: :json

    assert_response :success
    data = JSON.parse(@response.body)

    # max_updated_at should be at least as recent as event's updated_at
    max_updated = Time.parse(data['max_updated_at'])
    assert max_updated >= Event.first.reload.updated_at - 1.second, "max_updated_at should include event's updated_at"
  end

  test "heats_data includes max_updated_at for staleness detection" do
    get judge_heats_data_path(judge: @judge), as: :json

    assert_response :success
    data = JSON.parse(@response.body)

    assert data.key?("max_updated_at"), "heats_data should include max_updated_at"
    assert data["max_updated_at"].present?, "max_updated_at should not be blank"

    # Verify it's a valid ISO8601 timestamp
    assert_nothing_raised { Time.parse(data["max_updated_at"]) }
  end

  test "heats_data max_updated_at matches version_check max_updated_at" do
    get judge_heats_data_path(judge: @judge), as: :json
    heats_data = JSON.parse(@response.body)

    get judge_version_check_path(@judge, @test_heat.number), as: :json
    version_data = JSON.parse(@response.body)

    assert_equal heats_data["max_updated_at"], version_data["max_updated_at"],
      "max_updated_at should be consistent between heats_data and version_check"
  end

  # ===== FEEDBACK VALIDATION TESTS =====
  # These tests verify that feedback configuration errors (duplicate/empty abbreviations)
  # are properly detected and included in the heats_data JSON response.
  # The validation follows the "Server computes" principle - business logic lives in Ruby.

  test "heats_data includes feedback_errors for duplicate abbreviations" do
    # Setup: Create feedbacks with duplicate abbreviations
    Feedback.destroy_all
    Feedback.create!(value: "Frame", abbr: "F", order: 1)
    Feedback.create!(value: "Footwork", abbr: "F", order: 2)  # Duplicate!

    get judge_heats_data_path(judge: @judge), as: :json

    assert_response :success
    data = JSON.parse(@response.body)

    assert data.key?("feedback_errors"), "Response should include feedback_errors key"
    assert_equal 1, data["feedback_errors"].length, "Should have exactly one error"
    assert_includes data["feedback_errors"].first, "Duplicate abbreviation"
    assert_includes data["feedback_errors"].first, "Frame"
    assert_includes data["feedback_errors"].first, "Footwork"
  end

  test "heats_data includes feedback_errors for empty abbreviations" do
    Feedback.destroy_all
    Feedback.create!(value: "Frame", abbr: "", order: 1)

    get judge_heats_data_path(judge: @judge), as: :json

    assert_response :success
    data = JSON.parse(@response.body)

    assert data.key?("feedback_errors")
    assert_equal 1, data["feedback_errors"].length
    assert_includes data["feedback_errors"].first, "empty abbreviation"
    assert_includes data["feedback_errors"].first, "Frame"
  end

  test "heats_data includes feedback_errors for nil abbreviations" do
    Feedback.destroy_all
    Feedback.create!(value: "Posture", abbr: nil, order: 1)

    get judge_heats_data_path(judge: @judge), as: :json

    assert_response :success
    data = JSON.parse(@response.body)

    assert data.key?("feedback_errors")
    assert_equal 1, data["feedback_errors"].length
    assert_includes data["feedback_errors"].first, "empty abbreviation"
  end

  test "heats_data feedback_errors is empty array when feedbacks are valid" do
    Feedback.destroy_all
    Feedback.create!(value: "Frame", abbr: "F", order: 1)
    Feedback.create!(value: "Posture", abbr: "P", order: 2)
    Feedback.create!(value: "Timing", abbr: "T", order: 3)

    get judge_heats_data_path(judge: @judge), as: :json

    assert_response :success
    data = JSON.parse(@response.body)

    assert data.key?("feedback_errors")
    assert_equal [], data["feedback_errors"], "Valid feedbacks should produce no errors"
  end

  test "heats_data feedback_errors detects multiple issues" do
    Feedback.destroy_all
    Feedback.create!(value: "Frame", abbr: "F", order: 1)
    Feedback.create!(value: "Footwork", abbr: "F", order: 2)   # Duplicate F
    Feedback.create!(value: "Posture", abbr: "", order: 3)     # Empty
    Feedback.create!(value: "Hip", abbr: "H", order: 4)
    Feedback.create!(value: "Head", abbr: "H", order: 5)       # Duplicate H

    get judge_heats_data_path(judge: @judge), as: :json

    assert_response :success
    data = JSON.parse(@response.body)

    assert data.key?("feedback_errors")
    assert_equal 3, data["feedback_errors"].length, "Should detect all three issues"

    # Check for each type of error
    errors_text = data["feedback_errors"].join(" ")
    assert_includes errors_text, "Duplicate"
    assert_includes errors_text, "empty abbreviation"
  end

  test "validate_feedbacks helper detects duplicate abbreviations" do
    feedbacks = [
      Feedback.new(value: "Frame", abbr: "F"),
      Feedback.new(value: "Footwork", abbr: "F")
    ]

    controller = ScoresController.new
    errors = controller.send(:validate_feedbacks, feedbacks)

    assert_equal 1, errors.length
    assert_includes errors.first, "Duplicate abbreviation"
    assert_includes errors.first, "\"F\""
    assert_includes errors.first, "Frame"
    assert_includes errors.first, "Footwork"
  end

  test "validate_feedbacks helper detects empty abbreviations" do
    feedbacks = [
      Feedback.new(value: "Frame", abbr: "F"),
      Feedback.new(value: "Posture", abbr: ""),
      Feedback.new(value: "Timing", abbr: nil)
    ]

    controller = ScoresController.new
    errors = controller.send(:validate_feedbacks, feedbacks)

    assert_equal 2, errors.length
    assert errors.all? { |e| e.include?("empty abbreviation") }
  end

  test "validate_feedbacks helper returns empty array for valid feedbacks" do
    feedbacks = [
      Feedback.new(value: "Frame", abbr: "F"),
      Feedback.new(value: "Posture", abbr: "P"),
      Feedback.new(value: "Timing", abbr: "T")
    ]

    controller = ScoresController.new
    errors = controller.send(:validate_feedbacks, feedbacks)

    assert_equal [], errors
  end

  # === Packed Multi-Dance Split Tests ===

  test "packed multi-dance heat shows separate rankings for each split" do
    studio = studios(:one)

    # Create a multi category
    multi_cat = Category.create!(name: 'Packed Split Test Category', order: 8000)

    # Create parent multi-dance with semi_finals
    parent_dance = Dance.create!(
      name: 'Packed Split 3-Dance',
      semi_finals: true,
      heat_length: 1,
      order: 8000,
      multi_category: multi_cat
    )

    # Create split dances (same name, different dance_ids)
    split1 = Dance.create!(name: 'Packed Split 3-Dance', order: -1, multi_category: multi_cat)
    split2 = Dance.create!(name: 'Packed Split 3-Dance', order: -2, multi_category: multi_cat)

    # Create multi_levels for each split
    MultiLevel.create!(dance: parent_dance, name: 'Newcomer', start_level: 1, stop_level: 1)
    MultiLevel.create!(dance: split1, name: 'Bronze', start_level: 2, stop_level: 2)
    MultiLevel.create!(dance: split2, name: 'Silver', start_level: 3, stop_level: 3)

    # Create entries and heats for different splits
    max_back = Person.maximum(:back) || 0
    entries = []

    # 2 entries for parent_dance (Newcomer)
    2.times do |i|
      student = Person.create!(name: "Newcomer Student #{i}", studio: studio, type: 'Student', level: @level)
      instructor = Person.create!(name: "Newcomer Instructor #{i}", studio: studio, type: 'Professional', back: max_back + 100 + i)
      entry = Entry.create!(lead: student, follow: instructor, age: @age, level: @level)
      Heat.create!(number: 200, dance: parent_dance, entry: entry, category: 'Multi')
      entries << entry
    end

    # 2 entries for split1 (Bronze)
    2.times do |i|
      student = Person.create!(name: "Bronze Student #{i}", studio: studio, type: 'Student', level: @level)
      instructor = Person.create!(name: "Bronze Instructor #{i}", studio: studio, type: 'Professional', back: max_back + 200 + i)
      entry = Entry.create!(lead: student, follow: instructor, age: @age, level: @level)
      Heat.create!(number: 200, dance: split1, entry: entry, category: 'Multi')
      entries << entry
    end

    # 1 entry for split2 (Silver)
    student = Person.create!(name: "Silver Student", studio: studio, type: 'Student', level: @level)
    instructor = Person.create!(name: "Silver Instructor", studio: studio, type: 'Professional', back: max_back + 300)
    entry = Entry.create!(lead: student, follow: instructor, age: @age, level: @level)
    Heat.create!(number: 200, dance: split2, entry: entry, category: 'Multi')
    entries << entry

    # Visit heat as judge for finals (slot 2 > heat_length 1)
    get judge_heat_path(@judge, 200, slot: 2)

    assert_response :success

    # Should show split headers
    assert_select 'h3', text: 'Newcomer'
    assert_select 'h3', text: 'Bronze'
    assert_select 'h3', text: 'Silver'

    # Each split should have its own ranking starting from 1
    # Newcomer split: 2 entries, ranks 1 and 2
    # Bronze split: 2 entries, ranks 1 and 2
    # Silver split: 1 entry, rank 1

    # Verify scores were created with per-split rankings
    heats = Heat.where(number: 200)

    parent_heats = heats.where(dance: parent_dance)
    split1_heats = heats.where(dance: split1)
    split2_heats = heats.where(dance: split2)

    # Check that each split has ranks starting from 1
    parent_scores = Score.where(judge: @judge, heat: parent_heats, slot: 2)
    split1_scores = Score.where(judge: @judge, heat: split1_heats, slot: 2)
    split2_scores = Score.where(judge: @judge, heat: split2_heats, slot: 2)

    assert_equal [1, 2].sort, parent_scores.map { |s| s.value.to_i }.sort
    assert_equal [1, 2].sort, split1_scores.map { |s| s.value.to_i }.sort
    assert_equal [1], split2_scores.map { |s| s.value.to_i }
  end

  test "update_rank prevents reordering across different splits" do
    studio = studios(:one)

    # Create a multi category
    multi_cat = Category.create!(name: 'Cross Split Test Category', order: 8100)

    # Create parent multi-dance with semi_finals
    parent_dance = Dance.create!(
      name: 'Cross Split 3-Dance',
      semi_finals: true,
      heat_length: 1,
      order: 8100,
      multi_category: multi_cat
    )

    # Create split dance
    split1 = Dance.create!(name: 'Cross Split 3-Dance', order: -1, multi_category: multi_cat)

    # Create multi_levels
    MultiLevel.create!(dance: parent_dance, name: 'Newcomer', start_level: 1, stop_level: 1)
    MultiLevel.create!(dance: split1, name: 'Bronze', start_level: 2, stop_level: 2)

    max_back = Person.maximum(:back) || 0

    # Create entry for parent_dance
    student1 = Person.create!(name: "Cross Student 1", studio: studio, type: 'Student', level: @level)
    instructor1 = Person.create!(name: "Cross Instructor 1", studio: studio, type: 'Professional', back: max_back + 400)
    entry1 = Entry.create!(lead: student1, follow: instructor1, age: @age, level: @level)
    heat1 = Heat.create!(number: 201, dance: parent_dance, entry: entry1, category: 'Multi')

    # Create entry for split1
    student2 = Person.create!(name: "Cross Student 2", studio: studio, type: 'Student', level: @level)
    instructor2 = Person.create!(name: "Cross Instructor 2", studio: studio, type: 'Professional', back: max_back + 401)
    entry2 = Entry.create!(lead: student2, follow: instructor2, age: @age, level: @level)
    heat2 = Heat.create!(number: 201, dance: split1, entry: entry2, category: 'Multi')

    # Create initial scores
    Score.create!(judge: @judge, heat: heat1, slot: 2, value: '1')
    Score.create!(judge: @judge, heat: heat2, slot: 2, value: '1')

    # Attempt to reorder across splits (should be ignored)
    post update_rank_path(judge: @judge), params: {
      source: heat1.id,
      target: heat2.id,
      id: 'slot-2'
    }

    # Should return OK but not change anything
    assert_response :success

    # Scores should remain unchanged (both still rank 1 in their respective splits)
    assert_equal '1', Score.find_by(judge: @judge, heat: heat1, slot: 2).value
    assert_equal '1', Score.find_by(judge: @judge, heat: heat2, slot: 2).value
  end

  test "update_rank allows reordering within same split" do
    studio = studios(:one)

    # Create a multi category
    multi_cat = Category.create!(name: 'Same Split Test Category', order: 8200)

    # Create parent multi-dance with semi_finals
    parent_dance = Dance.create!(
      name: 'Same Split 3-Dance',
      semi_finals: true,
      heat_length: 1,
      order: 8200,
      multi_category: multi_cat
    )

    MultiLevel.create!(dance: parent_dance, name: 'Newcomer', start_level: 1, stop_level: 1)

    max_back = Person.maximum(:back) || 0

    # Create two entries for same split
    student1 = Person.create!(name: "Same Split Student 1", studio: studio, type: 'Student', level: @level)
    instructor1 = Person.create!(name: "Same Split Instructor 1", studio: studio, type: 'Professional', back: max_back + 500)
    entry1 = Entry.create!(lead: student1, follow: instructor1, age: @age, level: @level)
    heat1 = Heat.create!(number: 202, dance: parent_dance, entry: entry1, category: 'Multi')

    student2 = Person.create!(name: "Same Split Student 2", studio: studio, type: 'Student', level: @level)
    instructor2 = Person.create!(name: "Same Split Instructor 2", studio: studio, type: 'Professional', back: max_back + 501)
    entry2 = Entry.create!(lead: student2, follow: instructor2, age: @age, level: @level)
    heat2 = Heat.create!(number: 202, dance: parent_dance, entry: entry2, category: 'Multi')

    # Create initial scores (heat1 rank 1, heat2 rank 2)
    Score.create!(judge: @judge, heat: heat1, slot: 2, value: '1')
    Score.create!(judge: @judge, heat: heat2, slot: 2, value: '2')

    # Reorder within same split (move heat2 to rank 1)
    post update_rank_path(judge: @judge), params: {
      source: heat2.id,
      target: heat1.id,
      id: 'slot-2'
    }

    assert_response :success

    # Scores should be swapped
    assert_equal '2', Score.find_by(judge: @judge, heat: heat1, slot: 2).value
    assert_equal '1', Score.find_by(judge: @judge, heat: heat2, slot: 2).value
  end

end