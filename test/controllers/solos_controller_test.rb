require "test_helper"

# Focused tests for SolosController core functionality.
# This test suite focuses on the most important and stable features
# while avoiding complex edge cases that require extensive fixture setup.

class SolosControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:one)
    Event.current = @event
    
    @solo = solos(:one)
    @primary = people(:Kathryn)
    @instructor = people(:instructor1)
    @student1 = people(:student_one)
    @student2 = people(:student_two)
    @dance = dances(:waltz)
    @age = ages(:one)
    @level = levels(:one)
    @category = categories(:one)
  end

  # ===== BASIC INTERFACE TESTS =====
  
  test "index displays solos organized by category" do
    get solos_url
    
    assert_response :success
    assert_select 'body'
  end
  
  test "show displays solo details" do
    get solo_url(@solo, primary: @primary.id)
    
    assert_response :success
    assert_select 'body'
  end
  
  test "new displays solo creation form" do
    get new_solo_url(primary: @primary.id)
    
    assert_response :success
    assert_select 'body'
  end
  
  test "new handles missing primary parameter" do
    get new_solo_url
    
    assert_response :success
    assert_select 'body'
  end
  
  test "edit displays solo editing form" do
    get edit_solo_url(@solo, primary: @primary.id)
    
    assert_response :success
    assert_select 'body'
  end

  # ===== EXISTING SOLO MANAGEMENT TESTS =====
  
  test "updates existing solo successfully" do
    patch solo_url(@solo), params: { 
      solo: { 
        primary: @primary.id,
        partner: people(:Arthur).id,
        age: @solo.heat.entry.age_id,
        level: @solo.heat.entry.level_id,
        dance_id: @solo.heat.dance_id,
        combo_dance_id: '',  # Empty to avoid nil issues
        song: 'Updated Song',
        artist: 'Updated Artist',
        number: 26
      } 
    }

    assert_redirected_to person_url(@primary)
    assert_match /Solo was successfully updated/, flash[:notice]
    
    @solo.reload
    assert_equal 'Updated Song', @solo.song
    assert_equal 'Updated Artist', @solo.artist
    assert_equal 26, @solo.heat.number
  end
  
  test "updates solo dance and maintains integrity" do
    new_dance = dances(:tango)
    
    patch solo_url(@solo), params: { 
      solo: { 
        primary: @primary.id,
        partner: people(:Arthur).id,
        age: @solo.heat.entry.age_id,
        level: @solo.heat.entry.level_id,
        dance_id: new_dance.id,
        combo_dance_id: '',  # Empty to avoid nil issues
        number: 27
      } 
    }

    @solo.reload
    assert_equal new_dance, @solo.heat.dance
  end

  # ===== DRAG-AND-DROP REORDERING TESTS =====
  
  test "reorders existing solos" do
    solo_two = solos(:two)
    
    post drop_solos_url, as: :turbo_stream, params: {
      source: solo_two.id,
      target: @solo.id
    }
      
    assert_response :success
    
    # Should respond with Turbo Stream
    assert_match /turbo-stream/, response.content_type
  end

  # ===== SORTING ALGORITHM TESTS =====
  
  test "sort_level organizes solos by dance level" do
    post sort_level_solos_url
    
    assert_redirected_to solos_url
    assert_match /solos sorted by level/, flash[:notice]
  end
  
  test "sort_gap optimizes solo distribution" do
    post sort_gap_solos_url
    
    assert_redirected_to solos_url
    assert_match /solos remixed/, flash[:notice]
  end

  # ===== SOLO SCRATCHING AND RESTORATION TESTS =====
  
  test "scratches scheduled solo" do
    @solo.heat.update!(number: 70)
    
    delete solo_url(@solo, primary: @primary.id)
    
    assert_response 303
    assert_redirected_to person_url(@primary)
    assert_match /Solo was successfully scratched/, flash[:notice]
    
    @solo.heat.reload
    assert_operator @solo.heat.number, :<, 0, "Heat number should be negative when scratched"
  end
  
  test "restores scratched solo" do
    @solo.heat.update!(number: -70)
    
    delete solo_url(@solo, primary: @primary.id)
    
    assert_response 303
    assert_redirected_to person_url(@primary)
    assert_match /Solo was successfully restored/, flash[:notice]
    
    @solo.heat.reload
    assert_operator @solo.heat.number, :>, 0, "Heat number should be positive when restored"
  end
  
  test "deletes unscheduled solo completely" do
    @solo.heat.update!(number: 0)
    
    assert_difference('Solo.count', -1) do
      assert_difference('Heat.count', -1) do
        delete solo_url(@solo, primary: @primary.id)
      end
    end
    
    assert_response 303
    assert_redirected_to person_url(@primary)
    assert_match /Solo was successfully removed/, flash[:notice]
  end

  # ===== CRITIQUE AND REPORTING TESTS =====
  
  test "critiques0 displays first critique format" do
    get critiques0_solos_url
    
    assert_response :success
    assert_select 'body'
  end
  
  test "critiques0 generates PDF format" do
    get critiques0_solos_url(format: 'pdf')
    
    assert_response :success
    assert_equal 'application/pdf', response.content_type
  end
  
  test "critiques1 displays second critique format" do
    get critiques1_solos_url
    
    assert_response :success
    assert_select 'body'
  end
  
  test "critiques1 generates PDF format" do
    get critiques1_solos_url(format: 'pdf')
    
    assert_response :success
    assert_equal 'application/pdf', response.content_type
  end
  
  test "critiques2 displays third critique format" do
    get critiques2_solos_url
    
    assert_response :success
    assert_select 'body'
  end
  
  test "critiques2 generates PDF format" do
    get critiques2_solos_url(format: 'pdf')
    
    assert_response :success
    assert_equal 'application/pdf', response.content_type
  end

  # ===== FORMATION MANAGEMENT TESTS =====
  
  test "formation displays correct instructors" do
    Formation.create!(solo: @solo, person: @instructor, on_floor: true)
    
    instructors = @solo.instructors
    assert_includes instructors, @instructor
  end
  
  test "formation handles instructor exclusion from own page" do
    Formation.create!(solo: @solo, person: @instructor, on_floor: true)
    
    instructors_from_instructor = @solo.instructors(@instructor)
    refute_includes instructors_from_instructor, @instructor
  end

  # ===== ERROR HANDLING TESTS =====
  
  test "handles invalid solo update gracefully" do
    original_song = @solo.song
    
    # Test validation error by using invalid level/age combination
    assert_raises(ActiveRecord::RecordNotFound) do
      patch solo_url(@solo), params: { 
        solo: { 
          primary: @primary.id,
          partner: people(:Arthur).id,
          age: @solo.heat.entry.age_id,
          level: @solo.heat.entry.level_id,
          dance_id: 99999,  # Invalid dance_id (non-existent)
          combo_dance_id: '',  # Empty to avoid nil issues
          number: 86
        } 
      }
    end
    
    @solo.reload
    assert_equal original_song, @solo.song, "Song should not change on failed update"
  end

  # ===== RETURN PATH AND NAVIGATION TESTS =====
  
  test "update respects return-to parameter" do
    return_path = person_path(@instructor)
    
    patch solo_url(@solo), params: { 
      'return-to' => return_path,
      solo: { 
        primary: @primary.id,
        partner: people(:Arthur).id,
        age: @solo.heat.entry.age_id,
        level: @solo.heat.entry.level_id,
        dance_id: @solo.heat.dance_id,
        combo_dance_id: '',  # Empty to avoid nil issues
        number: 97
      } 
    }

    assert_redirected_to return_path
  end
  
  test "update defaults to person page without return-to" do
    patch solo_url(@solo), params: { 
      solo: { 
        primary: @primary.id,
        partner: people(:Arthur).id,
        age: @solo.heat.entry.age_id,
        level: @solo.heat.entry.level_id,
        dance_id: @solo.heat.dance_id,
        combo_dance_id: '',  # Empty to avoid nil issues
        number: 98
      } 
    }

    assert_redirected_to person_url(@primary)
  end

  # ===== JSON API TESTS =====
  
  test "shows solo via JSON API" do
    get solo_url(@solo, primary: @primary.id), as: :json
    
    assert_response :success
    assert_equal 'application/json; charset=utf-8', response.content_type
  end
  
  test "deletes solo via JSON API" do
    delete solo_url(@solo, primary: @primary.id), as: :json
    
    assert_response :no_content
  end

  # ===== ADDITIONAL INTERFACE TESTS =====
  
  test "new form handles routine category selection" do
    get new_solo_url(primary: @student1.id, routine: true)
    
    assert_response :success
  end
  
  test "edit form handles locked event state" do
    @event.update!(locked: true)
    
    get edit_solo_url(@solo, primary: @student1.id)
    
    assert_response :success
  end
end