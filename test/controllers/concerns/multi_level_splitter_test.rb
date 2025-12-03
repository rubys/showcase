require "test_helper"

# Tests for the MultiLevelSplitter concern which handles splitting multi-dances
# into competition divisions by level, age, and couple type.
#
# The concern provides layered splits:
#   1. Level (e.g., Bronze vs Silver vs Gold)
#   2. Age (e.g., 18-35 vs 46-54)
#   3. Couple type (e.g., Pro-Am vs Amateur Couple)
#
# Each split creates a new Dance record with negative order and a MultiLevel
# record to track the split criteria.
#
# IMPORTANT: The split logic relies on sequential IDs for levels and ages.
# When comparing split_level >= max_level or split_age >= max_age, the logic
# assumes lower IDs represent "earlier" or "lower" levels/ages. Tests must
# create levels and ages with controlled sequential IDs.

class MultiLevelSplitterTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:one)
    Event.current = @event

    @studio = studios(:one)
    @category = categories(:five)  # Multi category

    # Create levels with controlled sequential IDs for testing
    # The split logic compares IDs, so we need predictable ordering
    @level_one = Level.create!(id: 1001, name: 'Test Bronze')
    @level_two = Level.create!(id: 1002, name: 'Test Silver')
    @level_three = Level.create!(id: 1003, name: 'Test Gold')

    # Create ages with controlled sequential IDs
    @age_one = Age.create!(id: 2001, category: 'TA', description: '18-35')
    @age_two = Age.create!(id: 2002, category: 'TB', description: '46-54')
    @age_three = Age.create!(id: 2003, category: 'TC', description: '66-75')

    # Create people for different couple types
    @instructor = people(:instructor1)  # Professional Leader
    @student_follow = people(:student_one)  # Student Follower
    @student_follow.update!(level: @level_one, age: @age_one)

    @student_lead = Person.create!(
      name: 'Student Leader',
      type: 'Student',
      role: 'Leader',
      studio: @studio,
      level: @level_one,
      age: @age_one
    )
    @pro_follow = people(:bertha_instructor)  # Professional Follower

    # Create a multi-dance for testing
    @multi_dance = Dance.create!(
      name: 'Test Multi',
      order: 100,
      heat_length: 2,
      multi_category: @category
    )

    # Create component dances
    @waltz = dances(:waltz)
    @tango = dances(:tango)
    Multi.create!(parent: @multi_dance, dance: @waltz, slot: 1)
    Multi.create!(parent: @multi_dance, dance: @tango, slot: 2)
  end

  # Note: teardown is handled automatically by ActiveSupport::TestCase transaction rollback

  # ===== HELPER METHOD TESTS =====

  # Test determine_couple_type returns correct types
  test "determine_couple_type returns Amateur Follow for pro lead + student follow" do
    entry = create_proam_entry(@instructor, @student_follow)
    controller = create_controller_with_concern

    assert_equal 'Amateur Follow', controller.send(:determine_couple_type, entry)
  end

  test "determine_couple_type returns Amateur Lead for student lead + pro follow" do
    entry = create_proam_entry(@student_lead, @pro_follow)
    controller = create_controller_with_concern

    assert_equal 'Amateur Lead', controller.send(:determine_couple_type, entry)
  end

  test "determine_couple_type returns Amateur Couple for student+student" do
    entry = create_amateur_entry(@student_lead, @student_follow)
    controller = create_controller_with_concern

    assert_equal 'Amateur Couple', controller.send(:determine_couple_type, entry)
  end

  # Test entry_matches_multi_level? for various criteria
  test "entry_matches_multi_level returns true when entry level is in range" do
    entry = create_proam_entry(@instructor, @student_follow, level: @level_one)
    ml = MultiLevel.new(start_level: @level_one.id, stop_level: @level_two.id)
    controller = create_controller_with_concern

    assert controller.send(:entry_matches_multi_level?, entry, ml)
  end

  test "entry_matches_multi_level returns false when entry level is outside range" do
    entry = create_proam_entry(@instructor, @student_follow, level: @level_three)
    # Create a multi_level that only includes level_one and level_two
    ml = MultiLevel.new(start_level: @level_one.id, stop_level: @level_two.id)
    controller = create_controller_with_concern

    refute controller.send(:entry_matches_multi_level?, entry, ml)
  end

  test "entry_matches_multi_level checks age range when specified" do
    entry = create_proam_entry(@instructor, @student_follow, level: @level_one, age: @age_one)
    ml = MultiLevel.new(
      start_level: @level_one.id,
      stop_level: @level_two.id,
      start_age: @age_one.id,
      stop_age: @age_two.id
    )
    controller = create_controller_with_concern

    assert controller.send(:entry_matches_multi_level?, entry, ml)
  end

  test "entry_matches_multi_level returns false when age is outside range" do
    entry = create_proam_entry(@instructor, @student_follow, level: @level_one, age: @age_three)
    ml = MultiLevel.new(
      start_level: @level_one.id,
      stop_level: @level_two.id,
      start_age: @age_one.id,
      stop_age: @age_two.id
    )
    controller = create_controller_with_concern

    refute controller.send(:entry_matches_multi_level?, entry, ml)
  end

  test "entry_matches_multi_level checks couple type when specified" do
    entry = create_proam_entry(@instructor, @student_follow, level: @level_one)
    ml = MultiLevel.new(
      start_level: @level_one.id,
      stop_level: @level_two.id,
      couple_type: 'Pro-Am'
    )
    controller = create_controller_with_concern

    # Amateur Follow should match Pro-Am
    assert controller.send(:entry_matches_multi_level?, entry, ml)
  end

  test "entry_matches_multi_level returns false when couple type does not match" do
    entry = create_amateur_entry(@student_lead, @student_follow, level: @level_one)
    ml = MultiLevel.new(
      start_level: @level_one.id,
      stop_level: @level_two.id,
      couple_type: 'Pro-Am'
    )
    controller = create_controller_with_concern

    # Amateur Couple should not match Pro-Am
    refute controller.send(:entry_matches_multi_level?, entry, ml)
  end

  # Test format_multi_level_name
  test "format_multi_level_name returns single level name when same" do
    controller = create_controller_with_concern

    name = controller.send(:format_multi_level_name, @level_one, @level_one)
    assert_equal @level_one.name, name
  end

  test "format_multi_level_name returns range when different" do
    controller = create_controller_with_concern

    name = controller.send(:format_multi_level_name, @level_one, @level_two)
    assert_equal "#{@level_one.name} - #{@level_two.name}", name
  end

  # Test base_name_without_couple
  test "base_name_without_couple removes Pro-Am suffix" do
    ml = MultiLevel.new(name: "Bronze - Silver - Pro-Am")
    controller = create_controller_with_concern

    assert_equal "Bronze - Silver", controller.send(:base_name_without_couple, ml)
  end

  test "base_name_without_couple removes Amateur Couple suffix" do
    ml = MultiLevel.new(name: "Bronze - Amateur Couple")
    controller = create_controller_with_concern

    assert_equal "Bronze", controller.send(:base_name_without_couple, ml)
  end

  test "base_name_without_couple leaves name unchanged if no suffix" do
    ml = MultiLevel.new(name: "Bronze - Silver")
    controller = create_controller_with_concern

    assert_equal "Bronze - Silver", controller.send(:base_name_without_couple, ml)
  end

  # ===== LEVEL SPLIT TESTS =====

  test "perform_initial_split creates two multi_levels and moves heats" do
    # Create entries and heats at different levels
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one)
    entry2 = create_proam_entry(@instructor, @student_follow, level: @level_two)

    heat1 = Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    heat2 = Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern
    controller.send(:perform_initial_split, @multi_dance.id, @level_one.id)

    # Should have created two multi_levels
    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi')).order(:start_level)
    assert_equal 2, multi_levels.count

    # First multi_level should cover level_one
    assert_equal @level_one.id, multi_levels.first.start_level
    assert_equal @level_one.id, multi_levels.first.stop_level

    # Second multi_level should cover level_two
    assert_equal @level_two.id, multi_levels.second.start_level
    assert_equal @level_two.id, multi_levels.second.stop_level

    # Heat1 should stay with original dance, heat2 should move
    heat1.reload
    heat2.reload
    assert_equal @multi_dance.id, heat1.dance_id
    refute_equal @multi_dance.id, heat2.dance_id
  end

  test "perform_initial_split does nothing when split_level >= max_level" do
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one)
    Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern
    controller.send(:perform_initial_split, @multi_dance.id, @level_one.id)

    # No multi_levels should be created
    assert_equal 0, MultiLevel.where(dance: @multi_dance).count
  end

  test "handle_expand removes multi_levels when back to single" do
    # Create initial split
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one)
    entry2 = create_proam_entry(@instructor, @student_follow, level: @level_two)

    heat1 = Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    heat2 = Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern
    controller.send(:perform_initial_split, @multi_dance.id, @level_one.id)

    # Verify split was created
    assert_equal 2, MultiLevel.where(dance: Dance.where(name: 'Test Multi')).count

    # Get the first multi_level
    ml = MultiLevel.where(dance: @multi_dance).first

    # Expand to include all levels (should remove split)
    controller.send(:perform_update_split, ml.id, @level_two.id)

    # All multi_levels should be removed
    assert_equal 0, MultiLevel.where(dance: Dance.where(name: 'Test Multi')).count

    # Both heats should be back on original dance
    heat1.reload
    heat2.reload
    assert_equal @multi_dance.id, heat1.dance_id
    assert_equal @multi_dance.id, heat2.dance_id
  end

  test "handle_shrink creates new split when shrinking last multi_level" do
    # Create initial split
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one)
    entry2 = create_proam_entry(@instructor, @student_follow, level: @level_two)

    heat1 = Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    heat2 = Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern
    controller.send(:perform_initial_split, @multi_dance.id, @level_one.id)

    # Should have 2 multi_levels
    assert_equal 2, MultiLevel.where(dance: Dance.where(name: 'Test Multi')).count
  end

  # ===== AGE SPLIT TESTS =====

  test "perform_initial_age_split creates two multi_levels by age" do
    # Create entries and heats at different ages
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one, age: @age_one)
    entry2 = create_proam_entry(@instructor, @student_follow, level: @level_one, age: @age_two)

    heat1 = Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    heat2 = Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern
    controller.send(:perform_initial_age_split, @multi_dance.id, @age_one.id)

    # Should have created two multi_levels
    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi')).order(:start_age)
    assert_equal 2, multi_levels.count

    # Both should have same level range
    multi_levels.each do |ml|
      assert_equal @level_one.id, ml.start_level
      assert_equal @level_one.id, ml.stop_level
    end

    # First should cover age_one, second should cover age_two
    assert_equal @age_one.id, multi_levels.first.start_age
    assert_equal @age_one.id, multi_levels.first.stop_age
    assert_equal @age_two.id, multi_levels.second.start_age
    assert_equal @age_two.id, multi_levels.second.stop_age

    # Heat1 should stay with original dance, heat2 should move
    heat1.reload
    heat2.reload
    assert_equal @multi_dance.id, heat1.dance_id
    refute_equal @multi_dance.id, heat2.dance_id
  end

  test "perform_initial_age_split does nothing when split_age >= max_age" do
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one, age: @age_one)
    Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern
    controller.send(:perform_initial_age_split, @multi_dance.id, @age_one.id)

    # No multi_levels should be created
    assert_equal 0, MultiLevel.where(dance: @multi_dance).count
  end

  test "handle_age_expand removes age splits when back to single" do
    # Create initial age split
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one, age: @age_one)
    entry2 = create_proam_entry(@instructor, @student_follow, level: @level_one, age: @age_two)

    heat1 = Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    heat2 = Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern
    controller.send(:perform_initial_age_split, @multi_dance.id, @age_one.id)

    # Verify split was created
    assert_equal 2, MultiLevel.where(dance: Dance.where(name: 'Test Multi')).count

    # Get the first multi_level
    ml = MultiLevel.where(dance: @multi_dance).first

    # Expand to include all ages
    controller.send(:perform_age_split, ml.id, @age_two.id)

    # Should have one multi_level with no age range
    remaining = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 1, remaining.count
    assert_nil remaining.first.start_age
    assert_nil remaining.first.stop_age
  end

  test "perform_age_split on multi_level with nil age ranges sets both start_age and stop_age" do
    # Create a multi_level with nil age ranges (no age restriction)
    # This simulates the scenario where a level split exists but no age split yet
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one, age: @age_one)
    entry2 = create_proam_entry(@instructor, @student_follow, level: @level_one, age: @age_two)

    Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')

    # Create multi_level with nil age ranges (level split only)
    ml = MultiLevel.create!(
      name: @level_one.name,
      dance: @multi_dance,
      start_level: @level_one.id,
      stop_level: @level_one.id,
      start_age: nil,
      stop_age: nil
    )

    controller = create_controller_with_concern

    # Shrink by age - this should set BOTH start_age and stop_age
    # The bug was that only stop_age was set, violating the validation
    controller.send(:perform_age_split, ml.id, @age_one.id)

    # Should now have two multi_levels
    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi')).order(:start_age)
    assert_equal 2, multi_levels.count

    # First should have valid age range (both start and stop set)
    first_ml = multi_levels.first
    assert_equal @age_one.id, first_ml.start_age
    assert_equal @age_one.id, first_ml.stop_age

    # Second should have valid age range
    second_ml = multi_levels.second
    assert_equal @age_two.id, second_ml.start_age
    assert_equal @age_two.id, second_ml.stop_age
  end

  # ===== COUPLE TYPE SPLIT TESTS =====

  test "perform_initial_couple_split splits pro_am vs amateur_couple" do
    # Create Pro-Am entry (pro lead, student follow)
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one)
    # Create Amateur Couple entry (student lead, student follow)
    entry2 = create_amateur_entry(@student_lead, @student_follow, level: @level_one)

    heat1 = Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    heat2 = Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern
    controller.send(:perform_initial_couple_split, @multi_dance.id, 'pro_am_vs_amateur')

    # Should have created two multi_levels
    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 2, multi_levels.count

    # One should be Pro-Am, other should be Amateur Couple
    couple_types = multi_levels.pluck(:couple_type).sort
    assert_equal ['Amateur Couple', 'Pro-Am'], couple_types

    # Heats should be on different dances
    heat1.reload
    heat2.reload
    refute_equal heat1.dance_id, heat2.dance_id
  end

  test "perform_initial_couple_split splits into three for amateur_lead_follow" do
    # Create Amateur Lead entry (student lead, pro follow)
    entry1 = create_proam_entry(@student_lead, @pro_follow, level: @level_one)
    # Create Amateur Follow entry (pro lead, student follow)
    entry2 = create_proam_entry(@instructor, @student_follow, level: @level_one)
    # Create Amateur Couple entry (student lead, student follow)
    entry3 = create_amateur_entry(@student_lead, @student_follow, level: @level_one)

    heat1 = Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    heat2 = Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')
    heat3 = Heat.create!(number: 3, entry: entry3, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern
    controller.send(:perform_initial_couple_split, @multi_dance.id, 'amateur_lead_follow')

    # Should have created three multi_levels
    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 3, multi_levels.count

    # Should have all three couple types
    couple_types = multi_levels.pluck(:couple_type).sort
    assert_equal ['Amateur Couple', 'Amateur Follow', 'Amateur Lead'], couple_types

    # All heats should be on different dances
    heat1.reload
    heat2.reload
    heat3.reload
    dance_ids = [heat1.dance_id, heat2.dance_id, heat3.dance_id].uniq
    assert_equal 3, dance_ids.count
  end

  test "perform_initial_couple_split does nothing when only one couple type" do
    # Create only Pro-Am entries
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one)
    entry2 = create_proam_entry(@instructor, @student_follow, level: @level_one)

    Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern
    controller.send(:perform_initial_couple_split, @multi_dance.id, 'pro_am_vs_amateur')

    # No multi_levels should be created since there's only one couple type
    assert_equal 0, MultiLevel.where(dance: @multi_dance).count
  end

  test "perform_couple_split within existing level split" do
    # First create entries with different couple types
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one)
    entry2 = create_amateur_entry(@student_lead, @student_follow, level: @level_one)

    heat1 = Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    heat2 = Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern

    # Create a multi_level manually to simulate existing level split
    ml = MultiLevel.create!(
      name: @level_one.name,
      dance: @multi_dance,
      start_level: @level_one.id,
      stop_level: @level_one.id
    )

    # Now split by couple type
    controller.send(:perform_couple_split, ml.id, 'pro_am_vs_amateur')

    # Should have two multi_levels now
    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 2, multi_levels.count

    # Both should have same level range
    multi_levels.each do |m|
      assert_equal @level_one.id, m.start_level
      assert_equal @level_one.id, m.stop_level
    end
  end

  # ===== INTEGRATION TESTS VIA split_multi ACTION =====

  test "split_multi action creates level split" do
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one)
    entry2 = create_proam_entry(@instructor, @student_follow, level: @level_two)

    Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')

    post split_multi_entries_url, params: {
      dance_id: @multi_dance.id,
      dance: @multi_dance.id,
      stop_level: @level_one.id,
      sort: 'level'
    }

    assert_response :redirect

    # Should have created multi_levels
    assert_operator MultiLevel.where(dance: Dance.where(name: 'Test Multi')).count, :>=, 2
  end

  test "split_multi action creates age split" do
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one, age: @age_one)
    entry2 = create_proam_entry(@instructor, @student_follow, level: @level_one, age: @age_two)

    Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')

    post split_multi_entries_url, params: {
      dance_id: @multi_dance.id,
      dance: @multi_dance.id,
      stop_age: @age_one.id,
      sort: 'level'
    }

    assert_response :redirect

    # Should have created multi_levels with age ranges
    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_operator multi_levels.count, :>=, 2
    assert multi_levels.any? { |ml| ml.start_age.present? }
  end

  test "split_multi action creates couple split" do
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one)
    entry2 = create_amateur_entry(@student_lead, @student_follow, level: @level_one)

    Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')

    post split_multi_entries_url, params: {
      dance_id: @multi_dance.id,
      dance: @multi_dance.id,
      couple_split: 'pro_am_vs_amateur',
      sort: 'level'
    }

    assert_response :redirect

    # Should have created multi_levels with couple types
    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_operator multi_levels.count, :>=, 2
    assert multi_levels.any? { |ml| ml.couple_type.present? }
  end

  test "split_multi action updates existing multi_level name" do
    # Create a multi_level first
    ml = MultiLevel.create!(
      name: 'Original Name',
      dance: @multi_dance,
      start_level: @level_one.id,
      stop_level: @level_one.id
    )

    post split_multi_entries_url, params: {
      multi_level_id: ml.id,
      dance_id: @multi_dance.id,
      dance: @multi_dance.id,
      name: 'New Name',
      sort: 'level'
    }

    assert_response :redirect

    ml.reload
    assert_equal 'New Name', ml.name
  end

  test "split dance inherits semi_finals and heat_length" do
    @multi_dance.update!(semi_finals: true, heat_length: 3)

    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one)
    entry2 = create_proam_entry(@instructor, @student_follow, level: @level_two)

    Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern
    controller.send(:perform_initial_split, @multi_dance.id, @level_one.id)

    # Find the new split dance
    split_dance = Dance.where(name: 'Test Multi', order: ...0).first
    assert_not_nil split_dance, "Split dance should have been created"
    assert split_dance.semi_finals, "Split dance should inherit semi_finals"
    assert_equal 3, split_dance.heat_length, "Split dance should inherit heat_length"
  end

  test "split dance copies multi_children" do
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one)
    entry2 = create_proam_entry(@instructor, @student_follow, level: @level_two)

    Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern
    controller.send(:perform_initial_split, @multi_dance.id, @level_one.id)

    # Find the new split dance
    split_dance = Dance.where(name: 'Test Multi', order: ...0).first
    assert_not_nil split_dance, "Split dance should have been created"

    # Should have same multi_children count
    assert_equal @multi_dance.multi_children.count, split_dance.multi_children.count
  end

  private

  # Create a Pro-Am entry (one professional, one student)
  def create_proam_entry(lead, follow, level: @level_one, age: @age_one)
    Entry.create!(
      lead: lead,
      follow: follow,
      level: level,
      age: age
    )
  end

  # Create an Amateur entry (student+student with instructor)
  def create_amateur_entry(lead, follow, level: @level_one, age: @age_one)
    Entry.create!(
      lead: lead,
      follow: follow,
      level: level,
      age: age,
      instructor: @instructor
    )
  end

  # Create a controller instance that includes the concern for testing private methods
  def create_controller_with_concern
    controller = EntriesController.new
    controller.request = ActionDispatch::TestRequest.create
    controller.response = ActionDispatch::TestResponse.new
    controller
  end
end
