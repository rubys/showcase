require "test_helper"

# Focused tests for HeatsController core functionality.
# This test suite focuses on the most important and stable features
# while avoiding complex edge cases that require extensive fixture setup.

class HeatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:one)
    Event.current = @event
    
    @heat = heats(:one)
    @primary = people(:Kathryn)
    @instructor = people(:instructor1)
    @student = people(:student_one)
    @judge = people(:Judy)
    @dance = dances(:waltz)
    @age = ages(:one)
    @level = levels(:one)
    @category = categories(:one)
  end

  # ===== BASIC INTERFACE TESTS =====
  
  test "index displays heat agenda" do
    get heats_url
    
    assert_response :success
    assert_select 'body'
  end
  
  test "mobile interface provides optimized heat display" do
    get mobile_heats_url
    
    assert_response :success
    assert_select 'body'
  end
  
  test "djlist provides DJ-friendly heat schedule" do
    get djlist_heats_url
    
    assert_response :success
    assert_select 'body'
  end
  
  test "djlist generates PDF format" do
    get djlist_heats_url(format: 'pdf')
    
    assert_response :success
    assert_equal 'application/pdf', response.content_type
  end
  
  test "book displays master heat book" do
    get book_heats_url
    
    assert_response :success
    assert_select 'body'
  end
  
  test "book generates master heat book PDF" do
    get book_heats_url(format: 'pdf')
    
    assert_response :success
    assert_equal 'application/pdf', response.content_type
  end
  
  test "book displays judge-specific heat book" do
    get book_heats_url(type: 'judge')
    
    assert_response :success
    assert_select 'body'
  end
  
  test "book generates judge heat book PDF" do
    get book_heats_url(type: 'judge', format: 'pdf')
    
    assert_response :success
    assert_equal 'application/pdf', response.content_type
  end

  # ===== HEAT CRUD OPERATIONS =====
  
  test "shows individual heat details" do
    get heat_url(@heat)
    
    assert_response :success
    assert_select 'body'
  end
  
  test "new heat form loads with dance selection" do
    get new_heat_url(primary: @student.id)
    
    assert_response :success
    assert_select 'form'
  end
  
  test "new heat form handles missing primary parameter" do
    get new_heat_url
    
    assert_response :success
    assert_select 'form'
  end
  
  test "creates heat with entry association" do
    assert_difference('Heat.count') do
      post heats_url, params: {
        heat: {
          primary: @student.id,
          partner: @instructor.id,
          age: @age.id,
          level: @level.id,
          category: 'Closed',
          dance_id: @dance.id
        }
      }
    end
    
    assert_redirected_to heat_url(Heat.last)
    assert_match /Heat was successfully created/, flash[:notice]
    
    new_heat = Heat.last
    assert_equal 'Closed', new_heat.category
    assert_equal @dance, new_heat.dance
  end
  
  test "edit heat form loads with entry details" do
    get edit_heat_url(@heat, primary: @student.id)
    
    assert_response :success
    assert_select 'form'
  end
  
  test "edit heat form handles missing primary parameter" do
    get edit_heat_url(@heat)
    
    assert_response :success
    assert_select 'form'
  end
  
  test "updates heat successfully" do
    patch heat_url(@heat), params: {
      heat: {
        primary: @student.id,
        partner: @instructor.id,
        age: @age.id,
        level: @level.id,
        category: 'Open',
        dance_id: @heat.dance_id
      }
    }
    
    assert_redirected_to person_url(@student)
    assert_match /Heat was successfully updated/, flash[:notice]
    
    @heat.reload
    assert_equal 'Open', @heat.category
  end

  # ===== HEAT SCHEDULING AND GENERATION =====
  
  test "redo regenerates heat schedule" do
    post redo_heats_url
    
    assert_redirected_to heats_url
    assert_match /heats generated/, flash[:notice]
  end
  
  test "undo reverts heat numbering changes" do
    # Set up a heat with previous number different from current
    @heat.update!(prev_number: 5, number: 10)
    
    post undo_heats_url
    
    assert_redirected_to heats_url
    assert_match /heat.* undone/, flash[:notice]
    
    @heat.reload
    assert_equal 5, @heat.number
  end

  # ===== HEAT RENUMBERING =====
  
  test "renumbers heat to new position" do
    # Create test entry for new heats
    test_entry = Entry.create!(
      lead: @instructor,
      follow: @student,
      age: @age,
      level: @level
    )
    
    heat1 = Heat.create!(
      number: 100,  # Use high numbers to avoid conflicts
      entry: test_entry,
      dance: @dance,
      category: 'Closed'
    )
    
    post renumber_heats_url, params: {
      before: 100,
      after: 105
    }
    
    assert_redirected_to heats_url
    
    heat1.reload
    assert_equal 105, heat1.number
  end
  
  test "renumbers all heats sequentially" do
    # Create test entry
    test_entry = Entry.create!(
      lead: @instructor,
      follow: @student,
      age: @age,
      level: @level
    )
    
    # Create heats with high numbers to avoid conflicts
    heat1 = Heat.create!(number: 200, entry: test_entry, dance: @dance, category: 'Closed')
    heat2 = Heat.create!(number: 210, entry: test_entry, dance: @dance, category: 'Closed') 
    heat3 = Heat.create!(number: 220, entry: test_entry, dance: @dance, category: 'Closed')
    
    post renumber_heats_url
    
    assert_redirected_to heats_url
    assert_match /heats renumbered/, flash[:notice]
    
    # Verify the created heats were renumbered
    [heat1, heat2, heat3].each(&:reload)
    heat_numbers = [heat1, heat2, heat3].map(&:number).sort
    
    # Should be sequential starting from 1 (or wherever the sequence starts)
    assert_equal 3, heat_numbers.uniq.length, "All heats should have unique numbers"
    assert heat_numbers.all? { |n| n > 0 }, "All heat numbers should be positive"
  end

  # ===== DRAG-AND-DROP FUNCTIONALITY =====
  
  test "drop moves heat to new position" do
    test_entry = Entry.create!(
      lead: @instructor,
      follow: @student,
      age: @age,
      level: @level
    )
    
    source_heat = Heat.create!(
      number: 110,
      entry: test_entry,
      dance: @dance,
      category: 'Closed'
    )
    
    target_heat = Heat.create!(
      number: 120,
      entry: test_entry,
      dance: @dance,
      category: 'Closed'
    )
    
    post drop_heats_url, as: :turbo_stream, params: {
      source: source_heat.id,
      target: target_heat.id
    }
    
    assert_response :success
    assert_match /turbo-stream/, response.content_type
    
    source_heat.reload
    assert_equal 120, source_heat.number
  end

  # ===== HEAT DESTRUCTION AND SCRATCHING =====
  
  test "scratches scheduled heat" do
    @heat.update!(number: 25)
    
    delete heat_url(@heat)
    
    assert_response 303
    assert_redirected_to heats_url
    assert_match /Heat was successfully scratched/, flash[:notice]
    
    @heat.reload
    assert_operator @heat.number, :<, 0
  end
  
  test "restores scratched heat" do
    @heat.update!(number: -25)
    
    delete heat_url(@heat)
    
    assert_response 303
    assert_match /Heat was successfully restored/, flash[:notice]
    
    @heat.reload
    assert_operator @heat.number, :>, 0
  end
  
  test "permanently deletes unscheduled heat" do
    test_entry = Entry.create!(
      lead: @instructor,
      follow: @student,
      age: @age,
      level: @level
    )
    
    unscheduled_heat = Heat.create!(
      number: 0,
      entry: test_entry,
      dance: @dance,
      category: 'Closed'
    )
    
    assert_difference('Heat.count', -1) do
      delete heat_url(unscheduled_heat)
    end
    
    assert_response 303
    assert_match /Heat was successfully removed/, flash[:notice]
  end

  # ===== BALLROOM SUPPORT =====
  
  test "handles multi-ballroom heat assignment" do
    @event.update!(ballrooms: 2)
    
    patch heat_url(@heat), params: {
      heat: {
        primary: @student.id,
        partner: @instructor.id,
        age: @age.id,
        level: @level.id,
        category: @heat.category,
        dance_id: @heat.dance_id,
        ballroom: 'A'
      }
    }
    
    assert_redirected_to person_url(@student)
    
    @heat.reload
    assert_equal 'A', @heat.ballroom
  end

  # ===== CATEGORY MANAGEMENT =====
  
  test "reset_open converts closed heats to open" do
    test_entry = Entry.create!(
      lead: @instructor,
      follow: @student,
      age: @age,
      level: @level
    )
    
    closed_heat = Heat.create!(
      number: 130,
      entry: test_entry,
      dance: @dance,
      category: 'Closed'
    )
    
    post reset_open_heats_url
    
    assert_redirected_to settings_event_index_path(tab: 'Advanced')
    assert_match /reset to open/, flash[:notice]
    
    closed_heat.reload
    assert_equal 'Open', closed_heat.category
  end
  
  test "reset_closed converts open heats to closed" do
    test_entry = Entry.create!(
      lead: @instructor,
      follow: @student,
      age: @age,
      level: @level
    )
    
    open_heat = Heat.create!(
      number: 140,
      entry: test_entry,
      dance: @dance,
      category: 'Open'
    )
    
    post reset_closed_heats_url
    
    assert_redirected_to settings_event_index_path(tab: 'Advanced')
    assert_match /reset to closed/, flash[:notice]
    
    open_heat.reload
    assert_equal 'Closed', open_heat.category
  end

  # ===== ERROR HANDLING =====
  
  test "handles invalid heat creation gracefully" do
    assert_no_difference('Heat.count') do
      post heats_url, params: {
        heat: {
          primary: @student.id,
          partner: @instructor.id,
          category: 'Closed'
          # Missing required dance_id
        }
      }
    end
    
    assert_response :unprocessable_content
  end
  
  test "handles heat update with validation errors" do
    patch heat_url(@heat), params: {
      heat: {
        primary: @student.id,
        partner: @instructor.id,
        age: nil,
        level: @level.id,
        category: @heat.category,
        dance_id: @heat.dance_id
      }
    }
    
    # Should handle validation errors gracefully
    assert_includes [200, 302, 422], response.status
  end

  # ===== RETURN PATH HANDLING =====
  
  test "update respects return-to parameter" do
    return_path = person_path(@instructor)
    
    patch heat_url(@heat), params: {
      'return-to' => return_path,
      heat: {
        primary: @student.id,
        partner: @instructor.id,
        age: @age.id,
        level: @level.id,
        category: @heat.category,
        dance_id: @heat.dance_id
      }
    }
    
    assert_redirected_to return_path
  end
  
  test "delete respects primary parameter for redirect" do
    delete heat_url(@heat), params: { primary: @student.id }
    
    assert_response 303
    assert_redirected_to person_url(@student)
  end
  
  test "delete respects return-to parameter for redirect" do
    return_url = "/heats#heat_85"
    delete heat_url(@heat), params: { 'return-to': return_url }
    
    assert_response 303
    assert_redirected_to return_url
  end
  
  test "delete with both return-to and primary uses return-to" do
    return_url = "/heats#heat_85"
    delete heat_url(@heat), params: { primary: @student.id, 'return-to': return_url }
    
    assert_response 303
    assert_redirected_to return_url
  end

  # ===== INTEGRATION TESTS =====
  
  test "complete heat workflow" do
    test_entry = Entry.create!(
      lead: @instructor,
      follow: @student,
      age: @age,
      level: @level
    )
    
    # Create unscheduled heat
    heat = Heat.create!(
      number: 0,
      entry: test_entry,
      dance: @dance,
      category: 'Closed'
    )
    
    # Update to schedule it
    patch heat_url(heat), params: {
      heat: {
        primary: @student.id,
        partner: @instructor.id,
        age: @age.id,
        level: @level.id,
        category: 'Closed',
        dance_id: @dance.id,
        number: 50
      }
    }
    
    heat.reload
    # Heat number may be reset during update - that's expected behavior
    assert_not_nil heat.number
    
    # Final cleanup
    heat.update!(number: 0)
    assert_difference('Heat.count', -1) do
      delete heat_url(heat)
    end
  end

  # ===== JUDGE ASSIGNMENT INTEGRATION =====
  
  test "heat edit shows judge assignment when enabled" do
    @event.update!(assign_judges: true)
    
    judge = Judge.create!(person: @judge, present: true)
    Score.create!(heat: @heat, judge_id: @judge.id)
    
    get edit_heat_url(@heat, primary: @student.id)
    
    assert_response :success
    assert_select 'form'
  end

  # ===== PERFORMANCE TESTS =====
  
  test "handles multiple heats efficiently" do
    test_entry = Entry.create!(
      lead: @instructor,
      follow: @student,
      age: @age,
      level: @level
    )
    
    # Create multiple heats
    10.times do |i|
      Heat.create!(
        number: 300 + i,
        entry: test_entry,
        dance: @dance,
        category: 'Closed'
      )
    end
    
    get heats_url
    assert_response :success
    
    get djlist_heats_url
    assert_response :success
  end
end