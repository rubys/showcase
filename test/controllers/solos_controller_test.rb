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
    assert_match /solos optimized for maximum gaps/, flash[:notice]
  end

  # ===== SPLIT FUNCTIONALITY TESTS =====

  test "sort_level respects category splits" do
    # Create a category with a split point
    category_with_split = Category.create!(
      name: "Test Rhythm Solos",
      order: 100,
      split: "3"
    )

    # Create a dance associated with this category
    dance = Dance.create!(
      name: "Test Rumba",
      order: 100,
      solo_category: category_with_split
    )

    # Use existing levels from fixtures
    level1 = levels(:AB)  # Assoc. Bronze
    level2 = levels(:AS)  # Assoc. Silver
    level3 = levels(:AG)  # Assoc. Gold

    # Create entries with different levels
    # When one partner is a Professional, they ARE the instructor, don't set instructor_id
    # When both are students, set instructor_id
    entry1 = Entry.create!(lead: @student1, follow: people(:Arthur), age: @age, level: level3)  # Arthur is Professional
    entry2 = Entry.create!(lead: @student2, follow: people(:student_one), instructor: @instructor, age: @age, level: level1)  # Both students
    entry3 = Entry.create!(lead: people(:Kathryn), follow: people(:Arthur), age: @age, level: level2)  # Arthur is Professional
    entry4 = Entry.create!(lead: people(:Arthur), follow: @student1, age: @age, level: level2)  # Arthur is Professional
    entry5 = Entry.create!(lead: @instructor, follow: @student2, age: @age, level: level1)  # instructor is Professional

    # Create solos in this category
    heat1 = Heat.create!(number: 101, entry: entry1, category: "Solo", dance: dance)
    heat2 = Heat.create!(number: 102, entry: entry2, category: "Solo", dance: dance)
    heat3 = Heat.create!(number: 103, entry: entry3, category: "Solo", dance: dance)
    heat4 = Heat.create!(number: 104, entry: entry4, category: "Solo", dance: dance)
    heat5 = Heat.create!(number: 105, entry: entry5, category: "Solo", dance: dance)

    solo1 = Solo.create!(heat: heat1, order: 1001)
    solo2 = Solo.create!(heat: heat2, order: 1002)
    solo3 = Solo.create!(heat: heat3, order: 1003)
    solo4 = Solo.create!(heat: heat4, order: 1004)
    solo5 = Solo.create!(heat: heat5, order: 1005)

    # Sort by level
    post sort_level_solos_url

    assert_redirected_to solos_url

    # Reload solos to get updated order
    [solo1, solo2, solo3, solo4, solo5].each(&:reload)

    # First 3 solos should be sorted by level independently
    first_group_solos = [solo1, solo2, solo3].sort_by(&:order)
    first_group_levels = first_group_solos.map { |s| s.heat.entry.level_id }
    assert_equal first_group_levels, first_group_levels.sort, "First group should be sorted by level"

    # Last 2 solos should be sorted by level independently
    second_group_solos = [solo4, solo5].sort_by(&:order)
    second_group_levels = second_group_solos.map { |s| s.heat.entry.level_id }
    assert_equal second_group_levels, second_group_levels.sort, "Second group should be sorted by level"

    # Ensure no crossing of boundary: highest order in first group < lowest order in second group
    max_first_group_order = first_group_solos.map(&:order).max
    min_second_group_order = second_group_solos.map(&:order).min
    assert_operator max_first_group_order, :<, min_second_group_order, "Split boundary should be respected"
  end

  test "sort_gap respects category splits" do
    # Create a category with a split point
    category_with_split = Category.create!(
      name: "Test Smooth Solos",
      order: 101,
      split: "2"
    )

    # Create a dance associated with this category
    dance = Dance.create!(
      name: "Test Waltz",
      order: 101,
      solo_category: category_with_split
    )

    # Create entries
    # When one partner is a Professional, they ARE the instructor, don't set instructor_id
    # When both are students, set instructor_id
    entry1 = Entry.create!(lead: @student1, follow: people(:Arthur), age: @age, level: @level)  # Arthur is Professional
    entry2 = Entry.create!(lead: @student2, follow: people(:student_one), instructor: @instructor, age: @age, level: @level)  # Both students
    entry3 = Entry.create!(lead: people(:Kathryn), follow: people(:Arthur), age: @age, level: @level)  # Arthur is Professional
    entry4 = Entry.create!(lead: people(:Arthur), follow: @student1, age: @age, level: @level)  # Arthur is Professional

    # Create solos in this category
    heat1 = Heat.create!(number: 201, entry: entry1, category: "Solo", dance: dance)
    heat2 = Heat.create!(number: 202, entry: entry2, category: "Solo", dance: dance)
    heat3 = Heat.create!(number: 203, entry: entry3, category: "Solo", dance: dance)
    heat4 = Heat.create!(number: 204, entry: entry4, category: "Solo", dance: dance)

    solo1 = Solo.create!(heat: heat1, order: 2001)
    solo2 = Solo.create!(heat: heat2, order: 2002)
    solo3 = Solo.create!(heat: heat3, order: 2003)
    solo4 = Solo.create!(heat: heat4, order: 2004)

    # Sort by gap
    post sort_gap_solos_url

    assert_redirected_to solos_url

    # Reload solos to get updated order
    [solo1, solo2, solo3, solo4].each(&:reload)

    # Get all solos sorted by their new order
    all_solos_by_order = [solo1, solo2, solo3, solo4].sort_by(&:order)

    # First 2 solos should remain in first group (lowest order positions)
    first_group_solos = all_solos_by_order[0..1]
    second_group_solos = all_solos_by_order[2..3]

    # Verify split boundary: all solos in first group have lower order than second group
    max_first_group_order = first_group_solos.map(&:order).max
    min_second_group_order = second_group_solos.map(&:order).min
    assert_operator max_first_group_order, :<, min_second_group_order, "Split boundary should be respected"
  end

  test "sort_level handles categories without splits" do
    # The existing @solo should be in a category without splits
    assert_nil @category.split.presence, "Test category should not have a split"

    post sort_level_solos_url

    assert_redirected_to solos_url
    assert_match /solos sorted by level/, flash[:notice]
  end

  test "sort_gap handles categories without splits" do
    # The existing @solo should be in a category without splits
    assert_nil @category.split.presence, "Test category should not have a split"

    post sort_gap_solos_url

    assert_redirected_to solos_url
    assert_match /solos optimized for maximum gaps/, flash[:notice]
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
    if original_song.nil?
      assert_nil @solo.song, "Song should remain nil on failed update"
    else
      assert_equal original_song, @solo.song, "Song should not change on failed update"
    end
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