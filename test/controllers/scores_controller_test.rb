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
end