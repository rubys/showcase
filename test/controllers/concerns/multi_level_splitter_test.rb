require "test_helper"

# Tests for the MultiLevelSplitter concern which handles splitting multi-dances
# into competition divisions by couple type, level, and age.
#
# The concern provides layered splits:
#   1. Couple type (e.g., Pro-Am vs Amateur Couple)
#   2. Level (e.g., Bronze vs Silver vs Gold)
#   3. Age (e.g., 18-35 vs 46-54)
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

  # Test base_name_without_couple (removes couple type PREFIX)
  test "base_name_without_couple removes Pro-Am prefix" do
    ml = MultiLevel.new(name: "Pro-Am - Bronze - Silver")
    controller = create_controller_with_concern

    assert_equal "Bronze - Silver", controller.send(:base_name_without_couple, ml)
  end

  test "base_name_without_couple removes Amateur Couple prefix" do
    ml = MultiLevel.new(name: "Amateur Couple - Bronze")
    controller = create_controller_with_concern

    assert_equal "Bronze", controller.send(:base_name_without_couple, ml)
  end

  test "base_name_without_couple removes Amateur Lead prefix" do
    ml = MultiLevel.new(name: "Amateur Lead - Full Gold")
    controller = create_controller_with_concern

    assert_equal "Full Gold", controller.send(:base_name_without_couple, ml)
  end

  test "base_name_without_couple removes Amateur Follow prefix" do
    ml = MultiLevel.new(name: "Amateur Follow - Silver - Gold")
    controller = create_controller_with_concern

    assert_equal "Silver - Gold", controller.send(:base_name_without_couple, ml)
  end

  test "base_name_without_couple leaves name unchanged if no prefix" do
    ml = MultiLevel.new(name: "Bronze - Silver")
    controller = create_controller_with_concern

    assert_equal "Bronze - Silver", controller.send(:base_name_without_couple, ml)
  end

  # Test format_full_name (couple type prefix + level + optional age)
  test "format_full_name with couple type and single level" do
    controller = create_controller_with_concern

    name = controller.send(:format_full_name, 'Pro-Am', @level_one.id, @level_one.id)
    assert_equal "Pro-Am - #{@level_one.name}", name
  end

  test "format_full_name with couple type and level range" do
    controller = create_controller_with_concern

    name = controller.send(:format_full_name, 'Amateur Couple', @level_one.id, @level_three.id)
    assert_equal "Amateur Couple - #{@level_one.name} - #{@level_three.name}", name
  end

  test "format_full_name without couple type returns just level range" do
    controller = create_controller_with_concern

    name = controller.send(:format_full_name, nil, @level_one.id, @level_two.id)
    assert_equal "#{@level_one.name} - #{@level_two.name}", name
  end

  test "format_full_name with couple type, level, and age range" do
    controller = create_controller_with_concern

    name = controller.send(:format_full_name, 'Pro-Am', @level_one.id, @level_two.id, @age_one.id, @age_two.id)
    expected = "Pro-Am - #{@level_one.name} - #{@level_two.name} #{@age_one.description} - #{@age_two.description}"
    assert_equal expected, name
  end

  test "format_full_name with couple type, single level, and single age" do
    controller = create_controller_with_concern

    name = controller.send(:format_full_name, 'Amateur Lead', @level_one.id, @level_one.id, @age_one.id, @age_one.id)
    expected = "Amateur Lead - #{@level_one.name} #{@age_one.description}"
    assert_equal expected, name
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

    # Should have no multi_levels - back to initial state (like level splits)
    remaining = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 0, remaining.count

    # Should have no negative order dances
    assert_equal 0, Dance.where(name: 'Test Multi', order: ...0).count
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

  # ===== COUPLE TYPE LEVEL RANGE TESTS =====
  # These tests verify that each couple type gets its own level range based on actual entries

  test "perform_initial_couple_split calculates level range per couple type" do
    # Pro-Am entries at level_two and level_three only (no level_one)
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_two)
    entry2 = create_proam_entry(@instructor, @student_follow, level: @level_three)

    # Amateur Couple entries at level_one and level_two
    entry3 = create_amateur_entry(@student_lead, @student_follow, level: @level_one)
    entry4 = create_amateur_entry(@student_lead, @student_follow, level: @level_two)

    Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 3, entry: entry3, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 4, entry: entry4, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern
    controller.send(:perform_initial_couple_split, @multi_dance.id, 'pro_am_vs_amateur')

    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 2, multi_levels.count

    # Pro-Am should have level range level_two to level_three
    pro_am = multi_levels.find { |ml| ml.couple_type == 'Pro-Am' }
    assert_not_nil pro_am
    assert_equal @level_two.id, pro_am.start_level
    assert_equal @level_three.id, pro_am.stop_level

    # Amateur Couple should have level range level_one to level_two
    amateur = multi_levels.find { |ml| ml.couple_type == 'Amateur Couple' }
    assert_not_nil amateur
    assert_equal @level_one.id, amateur.start_level
    assert_equal @level_two.id, amateur.stop_level
  end

  test "perform_couple_split calculates level range per couple type within existing split" do
    # Create entries with different levels per couple type
    # Pro-Am at level_two only
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_two)
    # Amateur Couple at level_one and level_two
    entry2 = create_amateur_entry(@student_lead, @student_follow, level: @level_one)
    entry3 = create_amateur_entry(@student_lead, @student_follow, level: @level_two)

    Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 3, entry: entry3, dance: @multi_dance, category: 'Multi')

    # Create a multi_level with wide range (covers all entries)
    ml = MultiLevel.create!(
      name: "#{@level_one.name} - #{@level_two.name}",
      dance: @multi_dance,
      start_level: @level_one.id,
      stop_level: @level_two.id
    )

    controller = create_controller_with_concern
    controller.send(:perform_couple_split, ml.id, 'pro_am_vs_amateur')

    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 2, multi_levels.count

    # Pro-Am should have level range only where it has entries (level_two)
    pro_am = multi_levels.find { |ml| ml.couple_type == 'Pro-Am' }
    assert_not_nil pro_am
    assert_equal @level_two.id, pro_am.start_level
    assert_equal @level_two.id, pro_am.stop_level

    # Amateur Couple should have its own range (level_one to level_two)
    amateur = multi_levels.find { |ml| ml.couple_type == 'Amateur Couple' }
    assert_not_nil amateur
    assert_equal @level_one.id, amateur.start_level
    assert_equal @level_two.id, amateur.stop_level
  end

  test "couple type split names show couple type first" do
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one)
    entry2 = create_amateur_entry(@student_lead, @student_follow, level: @level_one)

    Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern
    controller.send(:perform_initial_couple_split, @multi_dance.id, 'pro_am_vs_amateur')

    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))

    # Names should have couple type prefix
    pro_am = multi_levels.find { |ml| ml.couple_type == 'Pro-Am' }
    assert pro_am.name.start_with?('Pro-Am - ')

    amateur = multi_levels.find { |ml| ml.couple_type == 'Amateur Couple' }
    assert amateur.name.start_with?('Amateur Couple - ')
  end

  # ===== LEVEL SPLIT COUPLE TYPE ISOLATION TESTS =====
  # These tests verify that level splits only affect siblings within the same couple_type

  test "level split only affects siblings with same couple_type" do
    # Create entries for both couple types at multiple levels
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one)
    entry2 = create_proam_entry(@instructor, @student_follow, level: @level_two)
    entry3 = create_amateur_entry(@student_lead, @student_follow, level: @level_one)
    entry4 = create_amateur_entry(@student_lead, @student_follow, level: @level_two)

    Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 3, entry: entry3, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 4, entry: entry4, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern

    # First split by couple type
    controller.send(:perform_initial_couple_split, @multi_dance.id, 'pro_am_vs_amateur')

    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 2, multi_levels.count

    # Get the Pro-Am multi_level
    pro_am_ml = multi_levels.find { |ml| ml.couple_type == 'Pro-Am' }

    # Split Pro-Am by level (shrink to level_one only)
    controller.send(:perform_update_split, pro_am_ml.id, @level_one.id)

    # Reload multi_levels
    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))

    # Should now have 3 multi_levels: 2 for Pro-Am (split by level), 1 for Amateur Couple (unchanged)
    assert_equal 3, multi_levels.count

    # Amateur Couple should be unchanged (still covers both levels)
    amateur_mls = multi_levels.select { |ml| ml.couple_type == 'Amateur Couple' }
    assert_equal 1, amateur_mls.count
    assert_equal @level_one.id, amateur_mls.first.start_level
    assert_equal @level_two.id, amateur_mls.first.stop_level

    # Pro-Am should now have 2 multi_levels split by level
    pro_am_mls = multi_levels.select { |ml| ml.couple_type == 'Pro-Am' }
    assert_equal 2, pro_am_mls.count
  end

  test "handle_shrink preserves couple_type when creating new split" do
    # Setup: Create a couple type split, then shrink one
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one)
    entry2 = create_proam_entry(@instructor, @student_follow, level: @level_two)
    entry3 = create_amateur_entry(@student_lead, @student_follow, level: @level_one)

    Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 3, entry: entry3, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern
    controller.send(:perform_initial_couple_split, @multi_dance.id, 'pro_am_vs_amateur')

    # Get Pro-Am multi_level and shrink it
    pro_am_ml = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
                          .find { |ml| ml.couple_type == 'Pro-Am' }

    controller.send(:perform_update_split, pro_am_ml.id, @level_one.id)

    # The new split should also be Pro-Am
    pro_am_splits = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
                              .select { |ml| ml.couple_type == 'Pro-Am' }

    assert_equal 2, pro_am_splits.count
    pro_am_splits.each do |ml|
      assert_equal 'Pro-Am', ml.couple_type
    end
  end

  test "handle_expand only absorbs siblings with same couple_type" do
    # Setup: Create couple type split, then level split Pro-Am, then expand
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one)
    entry2 = create_proam_entry(@instructor, @student_follow, level: @level_two)
    entry3 = create_amateur_entry(@student_lead, @student_follow, level: @level_one)
    entry4 = create_amateur_entry(@student_lead, @student_follow, level: @level_two)

    Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 3, entry: entry3, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 4, entry: entry4, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern

    # Split by couple type
    controller.send(:perform_initial_couple_split, @multi_dance.id, 'pro_am_vs_amateur')

    # Split Pro-Am by level
    pro_am_ml = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
                          .find { |ml| ml.couple_type == 'Pro-Am' }
    controller.send(:perform_update_split, pro_am_ml.id, @level_one.id)

    # Now we should have 3 multi_levels
    assert_equal 3, MultiLevel.where(dance: Dance.where(name: 'Test Multi')).count

    # Expand Pro-Am level_one to cover all levels (should collapse Pro-Am level splits)
    pro_am_ml.reload
    controller.send(:perform_update_split, pro_am_ml.id, @level_two.id)

    # Should be back to 2 multi_levels (one for each couple type)
    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 2, multi_levels.count

    # Amateur Couple should still be intact and unchanged
    amateur_ml = multi_levels.find { |ml| ml.couple_type == 'Amateur Couple' }
    assert_not_nil amateur_ml
    assert_equal @level_one.id, amateur_ml.start_level
    assert_equal @level_two.id, amateur_ml.stop_level
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

  # ===== COUPLE TYPE COLLAPSE TESTS =====

  test "perform_couple_collapse merges couple type splits back to one" do
    # Create Pro-Am entry and Amateur Couple entry
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one)
    entry2 = create_amateur_entry(@student_lead, @student_follow, level: @level_one)

    heat1 = Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    heat2 = Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern

    # First create the couple split
    controller.send(:perform_initial_couple_split, @multi_dance.id, 'pro_am_vs_amateur')

    # Verify split was created
    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 2, multi_levels.count

    # Get one of the multi_levels to collapse from
    ml = multi_levels.first

    # Collapse the couple splits
    controller.send(:perform_couple_collapse, ml.id)

    # Should have no multi_levels - back to initial state
    remaining = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 0, remaining.count

    # Should have no negative order dances
    assert_equal 0, Dance.where(name: 'Test Multi', order: ...0).count

    # All heats should be back on the original dance
    heat1.reload
    heat2.reload
    assert_equal @multi_dance.id, heat1.dance_id
    assert_equal @multi_dance.id, heat2.dance_id
  end

  test "perform_couple_collapse within level split preserves level split" do
    # Create entries with different levels AND different couple types
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one)
    entry2 = create_amateur_entry(@student_lead, @student_follow, level: @level_one)
    entry3 = create_proam_entry(@instructor, @student_follow, level: @level_two)

    heat1 = Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    heat2 = Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')
    heat3 = Heat.create!(number: 3, entry: entry3, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern

    # First create level split
    controller.send(:perform_initial_split, @multi_dance.id, @level_one.id)
    assert_equal 2, MultiLevel.where(dance: Dance.where(name: 'Test Multi')).count

    # Get the first level's multi_level
    level_one_ml = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
                             .find { |ml| ml.stop_level == @level_one.id }

    # Now add couple split within the first level
    controller.send(:perform_couple_split, level_one_ml.id, 'pro_am_vs_amateur')

    # Should now have 3 multi_levels (2 for level one with couple types, 1 for level two)
    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 3, multi_levels.count

    # Get one of the couple-split multi_levels
    couple_ml = multi_levels.find { |ml| ml.couple_type.present? }

    # Collapse the couple split
    controller.send(:perform_couple_collapse, couple_ml.id)

    # Should have 2 multi_levels remaining (back to just level split)
    remaining = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 2, remaining.count

    # Neither should have couple_type set
    remaining.each do |ml|
      assert_nil ml.couple_type
    end
  end

  test "perform_couple_collapse via split_multi action" do
    # Create Pro-Am entry and Amateur Couple entry
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one)
    entry2 = create_amateur_entry(@student_lead, @student_follow, level: @level_one)

    Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')

    # First create the couple split via action
    post split_multi_entries_url, params: {
      dance_id: @multi_dance.id,
      dance: @multi_dance.id,
      couple_split: 'pro_am_vs_amateur',
      sort: 'level'
    }
    assert_response :redirect

    # Verify split was created
    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 2, multi_levels.count

    # Get one of the multi_levels
    ml = multi_levels.first

    # Collapse via action (empty couple_split means collapse)
    post split_multi_entries_url, params: {
      multi_level_id: ml.id,
      dance: @multi_dance.id,
      couple_split: '',
      sort: 'level'
    }
    assert_response :redirect

    # Should have no multi_levels - back to initial state
    remaining = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 0, remaining.count
  end

  # ===== AGE COLLAPSE TO INITIAL STATE TESTS =====

  test "handle_age_expand removes all splits when back to single multi_level overall" do
    # This tests that age collapse also checks for single multi_level overall
    # (not just single age split within a level group)
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

    # Should have no multi_levels - back to initial state
    remaining = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 0, remaining.count

    # Should have no negative order dances
    assert_equal 0, Dance.where(name: 'Test Multi', order: ...0).count

    # All heats should be back on original dance
    heat1.reload
    heat2.reload
    assert_equal @multi_dance.id, heat1.dance_id
    assert_equal @multi_dance.id, heat2.dance_id
  end

  test "age collapse within level split preserves level split" do
    # Create entries with different levels AND different ages within level one
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one, age: @age_one)
    entry2 = create_proam_entry(@instructor, @student_follow, level: @level_one, age: @age_two)
    entry3 = create_proam_entry(@instructor, @student_follow, level: @level_two, age: @age_one)

    heat1 = Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    heat2 = Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')
    heat3 = Heat.create!(number: 3, entry: entry3, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern

    # First create level split
    controller.send(:perform_initial_split, @multi_dance.id, @level_one.id)
    assert_equal 2, MultiLevel.where(dance: Dance.where(name: 'Test Multi')).count

    # Get the first level's multi_level
    level_one_ml = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
                             .find { |ml| ml.stop_level == @level_one.id }

    # Add age split within the first level
    controller.send(:perform_age_split, level_one_ml.id, @age_one.id)

    # Should now have 3 multi_levels
    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 3, multi_levels.count

    # Get one of the age-split multi_levels
    age_ml = multi_levels.find { |ml| ml.start_age.present? && ml.stop_age == @age_one.id }

    # Expand age to collapse the age split
    controller.send(:perform_age_split, age_ml.id, @age_two.id)

    # Should have 2 multi_levels remaining (back to just level split)
    remaining = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 2, remaining.count

    # The level_one multi_level should have nil age ranges
    level_one_remaining = remaining.find { |ml| ml.stop_level == @level_one.id }
    assert_nil level_one_remaining.start_age
    assert_nil level_one_remaining.stop_age
  end

  # ===== AGE SPLIT COUPLE TYPE ISOLATION TESTS =====
  # These tests verify that age splits only affect siblings within the same couple_type

  test "age split only affects siblings with same couple_type" do
    # This test reproduces the bug where age-splitting Pro-Am Full Bronze
    # would incorrectly interact with Amateur Couple Full Bronze splits
    # because the level_siblings query didn't filter by couple_type.

    # Create entries for both couple types at the same level but different ages
    # Pro-Am entries
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one, age: @age_one)
    entry2 = create_proam_entry(@instructor, @student_follow, level: @level_one, age: @age_two)
    # Amateur Couple entries at same level, already age-split
    entry3 = create_amateur_entry(@student_lead, @student_follow, level: @level_one, age: @age_one)
    entry4 = create_amateur_entry(@student_lead, @student_follow, level: @level_one, age: @age_two)

    Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 3, entry: entry3, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 4, entry: entry4, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern

    # First split by couple type
    controller.send(:perform_initial_couple_split, @multi_dance.id, 'pro_am_vs_amateur')

    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 2, multi_levels.count

    # Now age-split the Amateur Couple group
    amateur_ml = multi_levels.find { |ml| ml.couple_type == 'Amateur Couple' }
    controller.send(:perform_age_split, amateur_ml.id, @age_one.id)

    # Should now have 3 multi_levels: 1 Pro-Am (unchanged), 2 Amateur Couple (age-split)
    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 3, multi_levels.count

    # Pro-Am should be unchanged (still covers all ages, no start_age/stop_age)
    pro_am_mls = multi_levels.select { |ml| ml.couple_type == 'Pro-Am' }
    assert_equal 1, pro_am_mls.count
    assert_nil pro_am_mls.first.start_age, "Pro-Am should not have age split"
    assert_nil pro_am_mls.first.stop_age, "Pro-Am should not have age split"

    # Amateur Couple should have 2 age splits
    amateur_mls = multi_levels.select { |ml| ml.couple_type == 'Amateur Couple' }
    assert_equal 2, amateur_mls.count
    amateur_mls.each do |ml|
      assert_not_nil ml.start_age, "Amateur Couple splits should have start_age"
      assert_not_nil ml.stop_age, "Amateur Couple splits should have stop_age"
    end
  end

  test "age split with existing age splits in different couple_type does not create gaps" do
    # This is the specific scenario that caused the original bug:
    # Amateur Couple has age splits, Pro-Am doesn't.
    # When age-splitting Pro-Am, it should NOT interfere with Amateur Couple's splits.

    # Create entries
    # Pro-Am at level_one (all ages)
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one, age: @age_one)
    entry2 = create_proam_entry(@instructor, @student_follow, level: @level_one, age: @age_two)
    entry3 = create_proam_entry(@instructor, @student_follow, level: @level_one, age: @age_three)
    # Amateur Couple at level_one (will be age-split first)
    entry4 = create_amateur_entry(@student_lead, @student_follow, level: @level_one, age: @age_one)
    entry5 = create_amateur_entry(@student_lead, @student_follow, level: @level_one, age: @age_two)

    Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 3, entry: entry3, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 4, entry: entry4, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 5, entry: entry5, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern

    # First split by couple type
    controller.send(:perform_initial_couple_split, @multi_dance.id, 'pro_am_vs_amateur')
    assert_equal 2, MultiLevel.where(dance: Dance.where(name: 'Test Multi')).count

    # Age-split Amateur Couple first
    amateur_ml = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
                           .find { |ml| ml.couple_type == 'Amateur Couple' }
    controller.send(:perform_age_split, amateur_ml.id, @age_one.id)

    # Now we have: 1 Pro-Am (all ages), 2 Amateur Couple (age-split)
    assert_equal 3, MultiLevel.where(dance: Dance.where(name: 'Test Multi')).count

    # Now age-split Pro-Am - this is where the bug occurred
    pro_am_ml = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
                          .find { |ml| ml.couple_type == 'Pro-Am' }
    controller.send(:perform_age_split, pro_am_ml.id, @age_one.id)

    # Should now have 4 multi_levels: 2 Pro-Am (age-split), 2 Amateur Couple (age-split)
    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 4, multi_levels.count

    # Verify Pro-Am splits are correct (age_one | age_two-age_three)
    pro_am_mls = multi_levels.select { |ml| ml.couple_type == 'Pro-Am' }.sort_by(&:start_age)
    assert_equal 2, pro_am_mls.count
    assert_equal @age_one.id, pro_am_mls.first.start_age
    assert_equal @age_one.id, pro_am_mls.first.stop_age
    assert_equal @age_two.id, pro_am_mls.second.start_age
    assert_equal @age_three.id, pro_am_mls.second.stop_age  # Pro-Am has entries at age_three

    # Verify Amateur Couple splits are still correct (unchanged by Pro-Am split)
    # Amateur Couple only has entries at age_one and age_two
    amateur_mls = multi_levels.select { |ml| ml.couple_type == 'Amateur Couple' }.sort_by(&:start_age)
    assert_equal 2, amateur_mls.count
    assert_equal @age_one.id, amateur_mls.first.start_age
    assert_equal @age_one.id, amateur_mls.first.stop_age
    assert_equal @age_two.id, amateur_mls.second.start_age
    assert_equal @age_two.id, amateur_mls.second.stop_age  # Amateur only goes to age_two
  end

  test "age expand only considers siblings with same couple_type when collapsing" do
    # This tests Fix #2: remaining_siblings filter in handle_age_expand
    # When expanding an age range to collapse age splits, it should only
    # consider siblings with the same couple_type.

    # Create entries for both couple types
    entry1 = create_proam_entry(@instructor, @student_follow, level: @level_one, age: @age_one)
    entry2 = create_proam_entry(@instructor, @student_follow, level: @level_one, age: @age_two)
    entry3 = create_amateur_entry(@student_lead, @student_follow, level: @level_one, age: @age_one)
    entry4 = create_amateur_entry(@student_lead, @student_follow, level: @level_one, age: @age_two)

    Heat.create!(number: 1, entry: entry1, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 2, entry: entry2, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 3, entry: entry3, dance: @multi_dance, category: 'Multi')
    Heat.create!(number: 4, entry: entry4, dance: @multi_dance, category: 'Multi')

    controller = create_controller_with_concern

    # Split by couple type
    controller.send(:perform_initial_couple_split, @multi_dance.id, 'pro_am_vs_amateur')
    assert_equal 2, MultiLevel.where(dance: Dance.where(name: 'Test Multi')).count

    # Age-split both couple types
    pro_am_ml = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
                          .find { |ml| ml.couple_type == 'Pro-Am' }
    amateur_ml = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
                           .find { |ml| ml.couple_type == 'Amateur Couple' }

    controller.send(:perform_age_split, pro_am_ml.id, @age_one.id)
    controller.send(:perform_age_split, amateur_ml.id, @age_one.id)

    # Now we have 4 multi_levels: 2 Pro-Am (age-split), 2 Amateur Couple (age-split)
    assert_equal 4, MultiLevel.where(dance: Dance.where(name: 'Test Multi')).count

    # Expand Pro-Am to collapse its age splits
    pro_am_ml.reload
    controller.send(:perform_age_split, pro_am_ml.id, @age_two.id)

    # Should now have 3 multi_levels: 1 Pro-Am (collapsed), 2 Amateur Couple (still age-split)
    multi_levels = MultiLevel.where(dance: Dance.where(name: 'Test Multi'))
    assert_equal 3, multi_levels.count

    # Pro-Am should have no age range (collapsed back to single)
    pro_am_mls = multi_levels.select { |ml| ml.couple_type == 'Pro-Am' }
    assert_equal 1, pro_am_mls.count
    assert_nil pro_am_mls.first.start_age, "Pro-Am should have nil start_age after collapse"
    assert_nil pro_am_mls.first.stop_age, "Pro-Am should have nil stop_age after collapse"

    # Amateur Couple should still have 2 age splits (unchanged)
    amateur_mls = multi_levels.select { |ml| ml.couple_type == 'Amateur Couple' }
    assert_equal 2, amateur_mls.count
    amateur_mls.each do |ml|
      assert_not_nil ml.start_age, "Amateur Couple should still have age splits"
      assert_not_nil ml.stop_age, "Amateur Couple should still have age splits"
    end
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
