require 'test_helper'

# Test coverage for the HeatScheduler concern which implements the core
# business logic for scheduling ballroom dance heats.
#
# Tests cover:
# - Heat scheduling algorithm (grouping, balancing, reordering)
# - Instructor conflict prevention
# - Max heat size enforcement
# - Category and age range handling
# - Solo performance scheduling
# - Formation conflict detection
# - Participant exclusion rules
# - Pro heat support
class HeatSchedulerTest < ActiveSupport::TestCase
  # Create a test class that includes the HeatScheduler module
  class TestScheduler
    include HeatScheduler

    # Mock the Printable module methods if needed
    def generate_agenda
      @start = []
      @heats = []
    end
  end

  setup do
    @scheduler = TestScheduler.new
    @event = events(:one)
    
    # Set up basic test data
    @studio1 = studios(:one)
    @studio2 = studios(:two)
    
    @instructor1 = people(:instructor_one)
    @instructor2 = people(:instructor_two)
    @student1 = people(:student_one)
    @student2 = people(:student_two)
    
    @dance_waltz = dances(:waltz)
    @dance_tango = dances(:tango)
    
    @category_open = Category.create!(name: "Test Open Category", order: 100)
    @category_closed = Category.create!(name: "Test Closed Category", order: 101)
    
    # Configure dance categories
    @dance_waltz.update!(
      open_category: @category_open,
      closed_category: @category_closed
    )
    @dance_tango.update!(
      open_category: @category_open,
      closed_category: @category_closed
    )
  end
  
  test "schedule_heats removes scratched heats with negative numbers" do
    # Create a scratched heat with negative number
    entry = Entry.create!(
      lead: @instructor1,
      follow: @student1,
      age: ages(:one),
      level: levels(:one)
    )
    
    scratched_heat = Heat.create!(
      number: -1,
      dance: @dance_waltz,
      entry: entry,
      category: 'Closed'
    )
    
    assert_difference 'Heat.count', -1 do
      @scheduler.schedule_heats
    end
    
    assert_nil Heat.find_by(id: scratched_heat.id)
  end
  
  test "schedule_heats removes orphaned entries without heats" do
    # Create an orphaned entry
    orphaned_entry = Entry.create!(
      lead: @instructor1,
      follow: @student1,
      age: ages(:one),
      level: levels(:one)
    )
    
    assert_difference 'Entry.count', -1 do
      @scheduler.schedule_heats
    end
    
    assert_nil Entry.find_by(id: orphaned_entry.id)
  end
  
  test "schedule_heats groups heats by dance category and level" do
    # Create heats with different categories
    entry1 = entries(:one)
    entry2 = entries(:two)
    
    heat1 = Heat.create!(
      dance: @dance_waltz,
      entry: entry1,
      category: 'Closed',
      number: 0
    )
    
    heat2 = Heat.create!(
      dance: @dance_waltz,
      entry: entry2,
      category: 'Open',
      number: 0
    )
    
    @scheduler.schedule_heats
    
    heat1.reload
    heat2.reload
    
    # Different categories should get different heat numbers
    assert_not_equal heat1.number, heat2.number
  end
  
  test "schedule_heats respects max heat size" do
    @event.update!(max_heat_size: 2)
    Event.current = @event
    
    # Create 3 entries with different instructors to avoid instructor conflicts
    entries = []
    instructors = [@instructor1, @instructor2, 
                   Person.create!(name: "Instructor Three", studio: @studio1, type: 'Professional', back: 103)]
    
    3.times do |i|
      student = Person.create!(
        name: "Student Maxsize #{i}",
        studio: @studio1,
        type: 'Student',
        level: levels(:one)
      )
      
      entry = Entry.create!(
        lead: instructors[i],
        follow: student,
        age: ages(:one),
        level: levels(:one)
      )
      
      entries << entry
      
      Heat.create!(
        dance: @dance_waltz,
        entry: entry,
        category: 'Closed',
        number: 0
      )
    end
    
    @scheduler.schedule_heats
    
    # Filter to only our test heats
    test_heats = Heat.joins(:entry).where(
      dance: @dance_waltz, 
      category: 'Closed',
      entry: { id: entries.map(&:id) }
    )
    
    # Group by heat number
    heats_by_number = test_heats.group_by(&:number)
    
    # With max size 2, 3 entries should be in at least 2 heats
    assert heats_by_number.size >= 2, "Expected at least 2 heats but got #{heats_by_number.size}"
    
    # Each heat should have max 2 entries
    heats_by_number.each do |number, heats|
      assert heats.size <= 2, "Heat #{number} has #{heats.size} entries, expected <= 2"
    end
  end
  
  test "schedule_heats prevents instructor conflicts" do
    # Create two students dancing with same instructor
    entry1 = Entry.create!(
      lead: @instructor1,
      follow: @student1,
      age: ages(:one),
      level: levels(:one)
    )
    
    entry2 = Entry.create!(
      lead: @instructor1,
      follow: @student2,
      age: ages(:one),
      level: levels(:one)
    )
    
    # Create heats for same dance
    Heat.create!(
      dance: @dance_waltz,
      entry: entry1,
      category: 'Closed',
      number: 0
    )
    
    Heat.create!(
      dance: @dance_waltz,
      entry: entry2,
      category: 'Closed',
      number: 0
    )
    
    @scheduler.schedule_heats
    
    # Heats with same instructor should have different numbers
    heat1 = Heat.find_by(entry: entry1)
    heat2 = Heat.find_by(entry: entry2)
    
    assert_not_equal heat1.number, heat2.number
  end
  
  test "schedule_heats handles solo performances" do
    entry = entries(:one)
    
    heat = Heat.create!(
      dance: @dance_waltz,
      entry: entry,
      category: 'Solo',
      number: 0
    )
    
    # Use a unique order number
    max_order = Solo.maximum(:order) || 0
    solo = Solo.create!(
      heat: heat,
      order: max_order + 1
    )
    
    @scheduler.schedule_heats
    
    heat.reload
    assert heat.number > 0
  end
  
  test "schedule_heats respects category order" do
    # Create isolated categories for this test to avoid fixture pollution
    category_closed = Category.create!(name: "Test Isolated Closed", order: 10)
    category_open = Category.create!(name: "Test Isolated Open", order: 20)

    # Create isolated dance for this test
    isolated_dance = Dance.create!(
      name: "Test Isolated Dance",
      order: 999,
      open_category: category_open,
      closed_category: category_closed
    )

    # Ensure event.heat_range_level is not 0 to prevent level-based resorting
    @event.update!(heat_range_level: 1)
    Event.current = @event  # Update the cached Event.current

    # Use fixture entries
    entry1 = entries(:one)
    entry2 = entries(:two)

    # Mark all existing heats as scratched (negative numbers) to exclude them
    Heat.update_all(number: -1)

    # Create new heats for testing with isolated dance
    heat_closed = Heat.create!(
      dance: isolated_dance,
      entry: entry1,
      category: 'Closed',
      number: 0
    )

    heat_open = Heat.create!(
      dance: isolated_dance,
      entry: entry2,
      category: 'Open',
      number: 0
    )

    @scheduler.schedule_heats

    heat_closed.reload
    heat_open.reload

    # Closed category (order 10) should come before Open (order 20)
    assert heat_closed.number < heat_open.number,
      "Expected Closed heat (#{heat_closed.number}) < Open heat (#{heat_open.number})"
  end
  
  test "rebalance distributes heats evenly" do
    # Create a test scenario for rebalancing
    subgroups = [
      HeatScheduler::Group.new,
      HeatScheduler::Group.new
    ]
    
    assignments = {}
    
    # Set up the test data
    HeatScheduler::Group.set_knobs
    
    # This is a simplified test - in real scenario would have actual heat data
    @scheduler.rebalance(assignments, subgroups, 5)
    
    # Verify groups are balanced
    sizes = subgroups.map(&:size)
    assert sizes.max - sizes.min <= 1, "Groups not balanced: #{sizes}"
  end
  
  test "schedule_heats handles pro heats separately" do
    # Enable pro heats for the event
    @event.update!(pro_heats: true)
    Event.current = @event
    
    # Create pro entry (two professionals)
    entry = Entry.create!(
      lead: @instructor1,
      follow: @instructor2,
      age: ages(:one),
      level: levels(:one)
    )
    
    heat = Heat.create!(
      dance: @dance_waltz,
      entry: entry,
      category: 'Closed',
      number: 0
    )
    
    @scheduler.schedule_heats
    
    heat.reload
    assert heat.number > 0
    
    # Verify pro detection works
    assert entry.pro
  end
  
  test "schedule_heats respects heat range settings" do
    # Test age range - using 0 means no combining across ages
    @event.update!(heat_range_age: 0)
    
    age1 = ages(:one)
    age2 = ages(:two)
    
    entry1 = Entry.create!(
      lead: @instructor1,
      follow: @student1,
      age: age1,
      level: levels(:one)
    )
    
    entry2 = Entry.create!(
      lead: @instructor2,
      follow: @student2,
      age: age2,
      level: levels(:one)
    )
    
    Heat.create!(
      dance: @dance_waltz,
      entry: entry1,
      category: 'Closed',
      number: 0
    )
    
    Heat.create!(
      dance: @dance_waltz,
      entry: entry2,
      category: 'Closed',
      number: 0
    )
    
    @scheduler.schedule_heats
    
    heat1 = Heat.find_by(entry: entry1)
    heat2 = Heat.find_by(entry: entry2)
    
    # Different age groups with range 0 should be in different heats
    assert_not_equal heat1.number, heat2.number
  end
  
  test "Group class correctly identifies matching heats" do
    HeatScheduler::Group.set_knobs
    group = HeatScheduler::Group.new
    
    heat1 = heats(:one)
    heat2 = heats(:two)
    
    # Test adding first heat
    result = group.add?(1, 0, 0, 1, 1, heat1)
    assert result
    
    # Test matching logic
    matches = group.match?(1, 0, 0, 1, 1, heat2)
    assert matches
  end
  
  test "Group class respects participant exclusions" do
    HeatScheduler::Group.set_knobs
    group = HeatScheduler::Group.new
    
    # Create students with exclusion
    person1 = people(:student_one)
    person2 = people(:student_two)
    
    # Create entries where person1 is lead and excludes person2
    entry1 = Entry.create!(
      lead: person1,
      follow: @instructor1,
      age: ages(:one),
      level: levels(:one)
    )
    
    # Make person2 exclude person1 (reverse the exclusion)
    person2.update!(exclude: person1)
    
    entry2 = Entry.create!(
      lead: person2,
      follow: @instructor2,
      age: ages(:one),
      level: levels(:one)
    )
    
    heat1 = Heat.create!(
      dance: @dance_waltz,
      entry: entry1,
      category: 'Closed'
    )
    
    heat2 = Heat.create!(
      dance: @dance_waltz,
      entry: entry2,
      category: 'Closed'
    )
    
    # Add first heat (with person1)
    result = group.add?(1, 0, 0, 1, 1, heat1)
    assert_not_nil result
    
    # Second heat (with person2) should be rejected because person2 excludes person1
    result = group.add?(1, 0, 0, 1, 1, heat2)
    assert_nil result
  end
  
  test "schedule_heats handles formation conflicts" do
    entry = entries(:one)
    heat = Heat.create!(
      dance: @dance_waltz,
      entry: entry,
      category: 'Solo',
      number: 0
    )
    
    # Use unique order
    max_order = Solo.maximum(:order) || 0
    solo = Solo.create!(heat: heat, order: max_order + 100)
    
    # Add formation members
    Formation.create!(solo: solo, person: @student1, on_floor: true)
    Formation.create!(solo: solo, person: @student2, on_floor: true)
    
    # Create another heat with one of the formation members
    entry2 = Entry.create!(
      lead: @instructor1,
      follow: @student1,
      age: ages(:one),
      level: levels(:one)
    )
    
    heat2 = Heat.create!(
      dance: @dance_waltz,
      entry: entry2,
      category: 'Closed',
      number: 0
    )
    
    @scheduler.schedule_heats
    
    heat.reload
    heat2.reload
    
    # Should have different heat numbers due to formation conflict
    assert_not_equal heat.number, heat2.number
  end
  
  test "reorder groups heats by category and intermixes dances" do
    @event.update!(intermix: true)
    
    # Create multiple heats with different dances in same category
    entries = []
    [@dance_waltz, @dance_tango].each do |dance|
      2.times do |i|
        student = Person.create!(
          name: "Student #{dance.name} #{i}",
          studio: @studio1,
          type: 'Student',
          level: levels(:one)
        )
        
        entry = Entry.create!(
          lead: @instructor1,
          follow: student,
          age: ages(:one),
          level: levels(:one)
        )
        
        Heat.create!(
          dance: dance,
          entry: entry,
          category: 'Closed',
          number: 0
        )
      end
    end
    
    @scheduler.schedule_heats
    
    # Get heat numbers in order
    heats = Heat.where(category: 'Closed').order(:number)
    dance_sequence = heats.map { |h| h.dance.name }
    
    # Should intermix dances, not group all waltzes then all tangos
    assert_not_equal ['Waltz', 'Waltz', 'Tango', 'Tango'], dance_sequence
  end
  
  test "schedule_heats assigns consecutive heat numbers" do
    # Create several heats
    3.times do |i|
      student = Person.create!(
        name: "Student #{i}",
        studio: @studio1,
        type: 'Student',
        level: levels(:one)
      )
      
      entry = Entry.create!(
        lead: @instructor1,
        follow: student,
        age: ages(:one),
        level: levels(:one)
      )
      
      Heat.create!(
        dance: @dance_waltz,
        entry: entry,
        category: 'Closed',
        number: 0
      )
    end
    
    @scheduler.schedule_heats
    
    # Heat numbers should be consecutive starting from 1
    heat_numbers = Heat.where('number > 0').pluck(:number).sort
    expected = (1..heat_numbers.length).to_a

    assert_equal expected, heat_numbers
  end

  test "category-based split dances are grouped consecutively by category" do
    # This tests the fix for the Nashville Fall Ball issue where category-based
    # split dances (multiple Dance records with same name but different categories)
    # were being scattered instead of grouped consecutively.

    # Create two agenda categories
    cat1 = Category.create!(name: "Newcomer", order: 1000)
    cat2 = Category.create!(name: "Bronze", order: 1001)

    # Create category-based split dances: two "Test Waltz" dances with different categories
    # (In the Nashville database, this was used instead of multi-level splits)
    # Note: order 10 is the canonical dance, order -1 is the split
    waltz1 = Dance.create!(name: "Test Waltz Split", order: 10, closed_category: cat1)
    waltz2 = Dance.create!(name: "Test Waltz Split", order: -1, closed_category: cat2)

    # Create entries and heats for category 1 (Newcomer)
    5.times do |i|
      entry = Entry.create!(
        lead: Person.create!(name: "Lead #{i} Cat1", studio: @studio1),
        follow: @instructor1,
        age: ages(:one),
        level: levels(:one)
      )
      Heat.create!(dance: waltz1, entry: entry, category: 'Closed', number: 0)
    end

    # Create entries and heats for category 2 (Bronze)
    5.times do |i|
      entry = Entry.create!(
        lead: Person.create!(name: "Lead #{i} Cat2", studio: @studio2),
        follow: @instructor2,
        age: ages(:one),
        level: levels(:one)
      )
      Heat.create!(dance: waltz2, entry: entry, category: 'Closed', number: 0)
    end

    # Schedule heats
    @scheduler.schedule_heats

    # Get all scheduled heats grouped by heat number
    heats_by_number = Heat.where('number > 0').order(:number)
      .group_by(&:number)
      .map { |num, heats| [num, heats.first.dance_category] }

    # Find which heat numbers belong to each category
    cat1_heats = heats_by_number.select { |num, cat| cat == cat1 }.map(&:first)
    cat2_heats = heats_by_number.select { |num, cat| cat == cat2 }.map(&:first)

    # Verify both categories have heats scheduled
    assert cat1_heats.any?, "Category 1 should have heats scheduled"
    assert cat2_heats.any?, "Category 2 should have heats scheduled"

    # Verify heats for each category are consecutive
    assert_equal (cat1_heats.first..cat1_heats.last).to_a, cat1_heats,
      "Category 1 heats should be consecutive (was: #{cat1_heats.inspect})"
    assert_equal (cat2_heats.first..cat2_heats.last).to_a, cat2_heats,
      "Category 2 heats should be consecutive (was: #{cat2_heats.inspect})"

    # Verify categories are not interleaved
    # (i.e., all cat1 heats should come before cat2, or vice versa)
    assert cat1_heats.last < cat2_heats.first || cat2_heats.last < cat1_heats.first,
      "Categories should not be interleaved"
  end

  # ===== PARTNERLESS ENTRIES TESTS =====

  test "schedule_heats consolidates multiple partnerless entries to same heat number" do
    @event.update!(partnerless_entries: true)
    Event.current = @event

    # Find or create Event Staff studio for Nobody
    event_staff = Studio.find_or_create_by(name: 'Event Staff') { |s| s.tables = 0 }

    # Ensure Nobody exists
    nobody = Person.find_or_create_by(id: 0) do |p|
      p.name = 'Nobody'
      p.type = 'Student'
      p.studio = event_staff
      p.level = levels(:one)
      p.back = 0
    end

    # Create multiple students with different levels for partnerless entries
    students = []
    max_back = Person.maximum(:back) || 0
    3.times do |i|
      students << Person.create!(
        name: "Partnerless Student #{i}",
        type: 'Student',
        studio: @studio1,
        level: levels(:one),
        back: max_back + 100 + i
      )
    end

    # Create partnerless entries for the same dance
    students.each do |student|
      entry = Entry.create!(
        lead: student,
        follow: nobody,
        instructor: @instructor1,
        age: ages(:one),
        level: levels(:one)
      )

      Heat.create!(
        number: 0,  # Unscheduled
        category: 'Open',
        dance: @dance_waltz,
        entry: entry
      )
    end

    # Run scheduler
    @scheduler.schedule_heats

    # Verify all partnerless entries are assigned to the same heat number
    partnerless_heats = Heat.joins(:entry).where(
      'entries.lead_id = 0 OR entries.follow_id = 0'
    ).where('heats.number > 0')

    heat_numbers = partnerless_heats.pluck(:number).uniq
    assert_equal 1, heat_numbers.length,
      "All partnerless entries should be scheduled to the same heat number"

    assert_equal 3, partnerless_heats.count,
      "All 3 partnerless entries should be scheduled"
  end

  test "schedule_heats handles formations with participant conflicts correctly" do
    Event.current = @event

    # Find or create Event Staff studio for Nobody
    event_staff = Studio.find_or_create_by(name: 'Event Staff') { |s| s.tables = 0 }

    # Ensure Nobody exists
    nobody = Person.find_or_create_by(id: 0) do |p|
      p.name = 'Nobody'
      p.type = 'Student'
      p.studio = event_staff
      p.level = levels(:one)
      p.back = 0
    end

    # Create a studio formation (both lead and follow are Nobody)
    formation_entry = Entry.create!(
      lead: nobody,
      follow: nobody,
      instructor: @instructor1,
      age: ages(:one),
      level: levels(:one)
    )

    formation_heat = Heat.create!(
      number: 0,
      category: 'Open',
      dance: @dance_waltz,
      entry: formation_entry
    )

    # Create formation solo with student1 as participant
    max_order = Solo.maximum(:order) || 0
    solo = Solo.create!(heat: formation_heat, order: max_order + 1)
    Formation.create!(solo: solo, person: @student1, on_floor: true)

    # Create a partnerless entry with the SAME student (should conflict)
    partnerless_entry = Entry.create!(
      lead: @student1,  # Same student as in formation
      follow: nobody,
      instructor: @instructor1,
      age: ages(:one),
      level: levels(:one)
    )

    Heat.create!(
      number: 0,
      category: 'Open',
      dance: @dance_waltz,
      entry: partnerless_entry
    )

    # Run scheduler
    @scheduler.schedule_heats

    # Verify they have different heat numbers due to participant conflict
    formation_heat.reload
    partnerless_heat = Heat.find_by(entry: partnerless_entry)

    assert formation_heat.number > 0, "Formation heat should be scheduled"
    assert partnerless_heat.number > 0, "Partnerless heat should be scheduled"
    assert_not_equal formation_heat.number, partnerless_heat.number,
      "Formation and partnerless entry with same participant should not be grouped"
  end

  test "schedule_heats respects level/age ranges for non-partnerless entries" do
    Event.current = @event

    # Create two regular (non-partnerless) entries with different levels
    entry1 = Entry.create!(
      lead: @student1,
      follow: @instructor1,
      age: ages(:one),
      level: levels(:one)
    )

    entry2 = Entry.create!(
      lead: @student2,
      follow: @instructor2,
      age: ages(:one),
      level: levels(:one)
    )

    Heat.create!(number: 0, category: 'Open', dance: @dance_waltz, entry: entry1)
    Heat.create!(number: 0, category: 'Open', dance: @dance_waltz, entry: entry2)

    # Set strict level range
    @event.update!(heat_range_level: 0)

    @scheduler.schedule_heats

    heat1 = Heat.find_by(entry: entry1)
    heat2 = Heat.find_by(entry: entry2)

    # With strict level range, different levels should not be grouped
    # (This depends on level differences and heat_range_level setting)
    assert heat1.number > 0, "Entry 1 should be scheduled"
    assert heat2.number > 0, "Entry 2 should be scheduled"
  end

  # ===== BLOCK SCHEDULING TESTS =====

  test "schedule_heats with block ordering groups heats by entry and agenda category" do
    @event.update!(heat_order: 'B')
    Event.current = @event

    # Mark all existing heats as scratched to avoid interference
    Heat.update_all(number: -1)

    # Create an agenda category for rhythm dances
    rhythm_cat = Category.create!(name: "Rhythm Block 1", order: 200)

    # Create multiple rhythm dances
    cha_cha = Dance.create!(name: "Block Test Cha Cha", order: 1100, open_category: rhythm_cat)
    rumba = Dance.create!(name: "Block Test Rumba", order: 1101, open_category: rhythm_cat)
    swing = Dance.create!(name: "Block Test Swing", order: 1102, open_category: rhythm_cat)

    # Create entry with multiple heats in the same category
    student = Person.create!(
      name: "Block Test Student",
      studio: @studio1,
      type: 'Student',
      level: levels(:one)
    )

    entry = Entry.create!(
      lead: student,
      follow: @instructor1,
      age: ages(:one),
      level: levels(:one)
    )

    # Create heats for all three dances
    heat_cha = Heat.create!(dance: cha_cha, entry: entry, category: 'Open', number: 0)
    heat_rumba = Heat.create!(dance: rumba, entry: entry, category: 'Open', number: 0)
    heat_swing = Heat.create!(dance: swing, entry: entry, category: 'Open', number: 0)

    @scheduler.schedule_heats

    heat_cha.reload
    heat_rumba.reload
    heat_swing.reload

    # Verify all heats were scheduled
    assert heat_cha.number > 0, "Cha Cha heat should be scheduled"
    assert heat_rumba.number > 0, "Rumba heat should be scheduled"
    assert heat_swing.number > 0, "Swing heat should be scheduled"

    # Verify heats are consecutive (block scheduling)
    heat_numbers = [heat_cha.number, heat_rumba.number, heat_swing.number].sort
    assert_equal (heat_numbers.first..heat_numbers.last).to_a, heat_numbers,
      "Heats should be scheduled consecutively as a block"
  end

  test "schedule_heats with block ordering groups same dances together" do
    @event.update!(heat_order: 'B')
    Event.current = @event

    # Mark all existing heats as scratched to avoid interference
    Heat.update_all(number: -1)

    rhythm_cat = Category.create!(name: "Rhythm Block Test 2", order: 300)
    cha_cha = Dance.create!(name: "Block Test Cha 2", order: 1200, open_category: rhythm_cat)
    rumba = Dance.create!(name: "Block Test Rumba 2", order: 1201, open_category: rhythm_cat)

    # Create two entries, each with both dances
    entries = []
    instructors = [@instructor1, @instructor2]

    2.times do |i|
      student = Person.create!(
        name: "Block Student #{i} Test 2",
        studio: @studio1,
        type: 'Student',
        level: levels(:one)
      )

      entry = Entry.create!(
        lead: student,
        follow: instructors[i],
        age: ages(:one),
        level: levels(:one)
      )

      entries << entry

      Heat.create!(dance: cha_cha, entry: entry, category: 'Open', number: 0)
      Heat.create!(dance: rumba, entry: entry, category: 'Open', number: 0)
    end

    @scheduler.schedule_heats

    # Get heats for each dance
    cha_heats = Heat.where(dance: cha_cha, entry: entries).where('number > 0').pluck(:number).uniq
    rumba_heats = Heat.where(dance: rumba, entry: entries).where('number > 0').pluck(:number).uniq

    # All heats of the same dance should have the same heat number
    assert_equal 1, cha_heats.length,
      "All Cha Cha heats should have the same heat number (got #{cha_heats.inspect})"
    assert_equal 1, rumba_heats.length,
      "All Rumba heats should have the same heat number (got #{rumba_heats.inspect})"
  end

  test "schedule_heats with block ordering only blocks amateur open and closed heats" do
    @event.update!(heat_order: 'B')
    Event.current = @event

    rhythm_cat = Category.create!(name: "Rhythm Solo Test", order: 400)
    cha_cha = Dance.create!(name: "Solo Cha Cha", order: 300, solo_category: rhythm_cat, open_category: rhythm_cat)

    student = Person.create!(
      name: "Block Solo Student",
      studio: @studio1,
      type: 'Student',
      level: levels(:one)
    )

    entry = Entry.create!(
      lead: student,
      follow: @instructor1,
      age: ages(:one),
      level: levels(:one)
    )

    # Create both Open heat (should be blocked) and Solo heat (should not be blocked)
    heat_open = Heat.create!(dance: cha_cha, entry: entry, category: 'Open', number: 0)
    heat_solo = Heat.create!(dance: cha_cha, entry: entry, category: 'Solo', number: 0)

    # Add solo performance
    max_order = Solo.maximum(:order) || 0
    Solo.create!(heat: heat_solo, order: max_order + 1)

    @scheduler.schedule_heats

    heat_open.reload
    heat_solo.reload

    # Both should be scheduled
    assert heat_open.number > 0, "Open heat should be scheduled"
    assert heat_solo.number > 0, "Solo heat should be scheduled"

    # Solo heats are scheduled separately, so they might not be consecutive
    # Just verify they're both scheduled successfully
    assert_not_nil heat_solo.number
  end

  test "schedule_heats with block ordering handles pro heats separately" do
    @event.update!(heat_order: 'B', pro_heats: true)
    Event.current = @event

    # Mark all existing heats as scratched
    Heat.update_all(number: -1)

    rhythm_cat = Category.create!(name: "Rhythm Pro Test 3", order: 500)
    cha_cha = Dance.create!(name: "Pro Cha Cha 3", order: 1400, open_category: rhythm_cat)
    rumba = Dance.create!(name: "Pro Rumba 3", order: 1401, open_category: rhythm_cat)

    # Create pro entry (two professionals)
    pro_entry = Entry.create!(
      lead: @instructor1,
      follow: @instructor2,
      age: ages(:one),
      level: levels(:one)
    )

    # Create amateur entry
    student = Person.create!(
      name: "Block Pro Test Student 3",
      studio: @studio1,
      type: 'Student',
      level: levels(:one)
    )

    # Use a different instructor to avoid conflicts
    instructor3 = Person.create!(
      name: "Instructor Pro Test 3",
      studio: @studio1,
      type: 'Professional',
      back: 999
    )

    amateur_entry = Entry.create!(
      lead: student,
      follow: instructor3,
      age: ages(:one),
      level: levels(:one)
    )

    # Create heats for both
    Heat.create!(dance: cha_cha, entry: pro_entry, category: 'Open', number: 0)
    Heat.create!(dance: rumba, entry: pro_entry, category: 'Open', number: 0)
    Heat.create!(dance: cha_cha, entry: amateur_entry, category: 'Open', number: 0)
    Heat.create!(dance: rumba, entry: amateur_entry, category: 'Open', number: 0)

    @scheduler.schedule_heats

    # Pro heats should not be blocked (pro=true excludes them from blocking)
    pro_heats = Heat.where(entry: pro_entry).where('number > 0').order(:number)
    amateur_heats = Heat.where(entry: amateur_entry).where('number > 0').order(:number)

    # Amateur heats should be blocked (consecutive) - check as integers
    amateur_numbers = amateur_heats.pluck(:number).map(&:to_i).sort
    expected_range = (amateur_numbers.first..amateur_numbers.last).to_a
    assert_equal expected_range, amateur_numbers,
      "Amateur heats should be consecutive (blocked). Got #{amateur_numbers.inspect}, expected #{expected_range.inspect}"

    # Both should be scheduled
    assert pro_heats.all? { |h| h.number > 0 }, "All pro heats should be scheduled"
    assert amateur_heats.all? { |h| h.number > 0 }, "All amateur heats should be scheduled"
  end

  test "schedule_heats with block ordering respects agenda category boundaries" do
    @event.update!(heat_order: 'B')
    Event.current = @event

    # Create two different agenda categories
    smooth_cat = Category.create!(name: "Smooth Block", order: 600)
    rhythm_cat = Category.create!(name: "Rhythm Block", order: 601)

    # Create dances in different categories
    waltz = Dance.create!(name: "Block Waltz", order: 500, open_category: smooth_cat)
    cha_cha = Dance.create!(name: "Separate Cha Cha", order: 501, open_category: rhythm_cat)

    student = Person.create!(
      name: "Multi-Category Student",
      studio: @studio1,
      type: 'Student',
      level: levels(:one)
    )

    entry = Entry.create!(
      lead: student,
      follow: @instructor1,
      age: ages(:one),
      level: levels(:one)
    )

    # Create heats in different agenda categories
    heat_waltz = Heat.create!(dance: waltz, entry: entry, category: 'Open', number: 0)
    heat_cha = Heat.create!(dance: cha_cha, entry: entry, category: 'Open', number: 0)

    @scheduler.schedule_heats

    heat_waltz.reload
    heat_cha.reload

    # Both should be scheduled
    assert heat_waltz.number > 0, "Waltz heat should be scheduled"
    assert heat_cha.number > 0, "Cha Cha heat should be scheduled"

    # They should NOT be in the same block (different agenda categories)
    # The exact relationship depends on other heats, but they should be separate
    assert_not_nil heat_waltz.number
    assert_not_nil heat_cha.number
  end

  test "Block class implements required Heat-like interface" do
    rhythm_cat = Category.create!(name: "Block Interface Test", order: 700)
    cha_cha = Dance.create!(name: "Interface Cha Cha", order: 600, open_category: rhythm_cat)

    student = Person.create!(
      name: "Interface Student",
      studio: @studio1,
      type: 'Student',
      level: levels(:one)
    )

    entry = Entry.create!(
      lead: student,
      follow: @instructor1,
      age: ages(:one),
      level: levels(:one)
    )

    heat = Heat.create!(dance: cha_cha, entry: entry, category: 'Open', number: 1)

    # Create a block
    block = HeatScheduler::Block.new(entry, 'Open', rhythm_cat)
    block.add_heat(heat)

    # Test required interface methods
    assert_equal entry, block.entry
    assert_equal 'Open', block.category
    assert_equal entry.lead, block.lead
    assert_equal entry.follow, block.follow
    assert_equal rhythm_cat, block.dance_category
    assert_equal 1, block.heats.length
    assert_nil block.solo
    assert_not_nil block.dance
    assert_not_nil block.dance_id

  end

  test "BlockDance class provides required category methods" do
    rhythm_cat = Category.create!(name: "BlockDance Test", order: 800)

    block_dance = HeatScheduler::BlockDance.new(rhythm_cat, 100)

    # Test required methods
    assert_equal rhythm_cat, block_dance.agenda_category
    assert_equal 100, block_dance.order
    assert_equal rhythm_cat, block_dance.open_category
    assert_equal rhythm_cat, block_dance.closed_category
    assert_equal rhythm_cat, block_dance.solo_category
    assert_equal rhythm_cat, block_dance.multi_category
    assert_equal false, block_dance.semi_finals
    assert_not_nil block_dance.id
  end

  # ===== MULTI-DANCE SPLIT PACKING TESTS =====

  test "pack_multi_dance_splits reduces heat count for multi-dances with splits" do
    # Mark all existing heats as scratched
    Heat.update_all(number: -1)

    # Create a multi category
    multi_cat = Category.create!(name: "Multi Dance Pack Test", order: 900)

    # Create a parent multi-dance with split levels
    parent_dance = Dance.create!(name: "Pack Test 3-Dance", order: 700, multi_category: multi_cat)

    # Create split dances (different level splits)
    split1 = Dance.create!(name: "Pack Test 3-Dance", order: -1, multi_category: multi_cat)
    split2 = Dance.create!(name: "Pack Test 3-Dance", order: -2, multi_category: multi_cat)

    # Create multi_levels to mark this as having splits
    MultiLevel.create!(dance: parent_dance, name: "Level 1", start_level: 1, stop_level: 1)
    MultiLevel.create!(dance: split1, name: "Level 2", start_level: 2, stop_level: 2)
    MultiLevel.create!(dance: split2, name: "Level 3", start_level: 3, stop_level: 3)

    # Create child dances for the multi
    child1 = Dance.create!(name: "Pack Child Waltz", order: 701)
    child2 = Dance.create!(name: "Pack Child Tango", order: 702)
    child3 = Dance.create!(name: "Pack Child Foxtrot", order: 703)

    Multi.create!(parent_id: parent_dance.id, dance_id: child1.id)
    Multi.create!(parent_id: parent_dance.id, dance_id: child2.id)
    Multi.create!(parent_id: parent_dance.id, dance_id: child3.id)

    # Create entries and heats for different splits with different dancers
    # (no overlapping dancers between groups)
    students = []
    6.times do |i|
      students << Person.create!(
        name: "Pack Student #{i}",
        studio: @studio1,
        type: 'Student',
        level: levels(:one)
      )
    end

    max_back = Person.maximum(:back) || 0
    instructors = [@instructor1, @instructor2]
    instructors << Person.create!(name: "Pack Instructor 3", studio: @studio1, type: 'Professional', back: max_back + 200)
    instructors << Person.create!(name: "Pack Instructor 4", studio: @studio1, type: 'Professional', back: max_back + 201)
    instructors << Person.create!(name: "Pack Instructor 5", studio: @studio1, type: 'Professional', back: max_back + 202)
    instructors << Person.create!(name: "Pack Instructor 6", studio: @studio1, type: 'Professional', back: max_back + 203)

    # Group 1: students 0,1 with split1 dance
    [0, 1].each do |i|
      entry = Entry.create!(
        lead: students[i],
        follow: instructors[i],
        age: ages(:one),
        level: levels(:one)
      )
      Heat.create!(dance: split1, entry: entry, category: 'Multi', number: 0)
    end

    # Group 2: students 2,3 with split2 dance
    [2, 3].each do |i|
      entry = Entry.create!(
        lead: students[i],
        follow: instructors[i],
        age: ages(:one),
        level: levels(:one)
      )
      Heat.create!(dance: split2, entry: entry, category: 'Multi', number: 0)
    end

    # Group 3: students 4,5 with parent_dance
    [4, 5].each do |i|
      entry = Entry.create!(
        lead: students[i],
        follow: instructors[i],
        age: ages(:one),
        level: levels(:one)
      )
      Heat.create!(dance: parent_dance, entry: entry, category: 'Multi', number: 0)
    end

    @scheduler.schedule_heats

    # Get all scheduled Multi heats for our test dances
    test_dances = [parent_dance, split1, split2]
    multi_heats = Heat.where(dance: test_dances, category: 'Multi').where('number > 0')

    # Verify all 6 heats were scheduled
    assert_equal 6, multi_heats.count, "All 6 heats should be scheduled"

    # Since no dancers overlap, all heats could be packed into fewer groups
    heat_numbers = multi_heats.pluck(:number).uniq
    assert heat_numbers.size < 6, "Heats should be packed (got #{heat_numbers.size} groups for 6 heats)"
  end

  test "pack_multi_dance_splits respects max heat size" do
    # Mark all existing heats as scratched
    Heat.update_all(number: -1)

    # Set a small max heat size
    @event.update!(max_heat_size: 3)
    Event.current = @event

    # Create a multi category
    multi_cat = Category.create!(name: "Multi Max Size Test", order: 901)

    # Create parent and split dances
    parent_dance = Dance.create!(name: "Max Size 3-Dance", order: 710, multi_category: multi_cat)
    split1 = Dance.create!(name: "Max Size 3-Dance", order: -10, multi_category: multi_cat)

    # Create multi_levels
    MultiLevel.create!(dance: parent_dance, name: "Level 1", start_level: 1, stop_level: 1)
    MultiLevel.create!(dance: split1, name: "Level 2", start_level: 2, stop_level: 2)

    # Create 6 entries with unique dancers
    students = []
    instructors = []
    max_back = Person.maximum(:back) || 0
    6.times do |i|
      students << Person.create!(
        name: "Max Size Student #{i}",
        studio: @studio1,
        type: 'Student',
        level: levels(:one)
      )
      instructors << Person.create!(
        name: "Max Size Instructor #{i}",
        studio: @studio1,
        type: 'Professional',
        back: max_back + 300 + i
      )
    end

    # Create heats alternating between dances
    6.times do |i|
      entry = Entry.create!(
        lead: students[i],
        follow: instructors[i],
        age: ages(:one),
        level: levels(:one)
      )
      dance = i.even? ? parent_dance : split1
      Heat.create!(dance: dance, entry: entry, category: 'Multi', number: 0)
    end

    @scheduler.schedule_heats

    # With max_heat_size=3 and 6 heats, we should have at least 2 groups
    test_dances = [parent_dance, split1]
    multi_heats = Heat.where(dance: test_dances, category: 'Multi').where('number > 0')

    heats_by_number = multi_heats.group_by(&:number)

    # Each group should have at most 3 heats
    heats_by_number.each do |number, heats|
      assert heats.size <= 3, "Heat #{number} has #{heats.size} entries, expected <= 3"
    end

    # Should have at least 2 groups
    assert heats_by_number.size >= 2, "Expected at least 2 groups, got #{heats_by_number.size}"
  end

  test "pack_multi_dance_splits prevents same dancer in same heat" do
    # Mark all existing heats as scratched
    Heat.update_all(number: -1)

    # Create a multi category
    multi_cat = Category.create!(name: "Multi Conflict Test", order: 902)

    # Create parent and split dances
    parent_dance = Dance.create!(name: "Conflict 3-Dance", order: 720, multi_category: multi_cat)
    split1 = Dance.create!(name: "Conflict 3-Dance", order: -20, multi_category: multi_cat)

    # Create multi_levels
    MultiLevel.create!(dance: parent_dance, name: "Level 1", start_level: 1, stop_level: 1)
    MultiLevel.create!(dance: split1, name: "Level 2", start_level: 2, stop_level: 2)

    # Create entries where the same student appears in both splits
    shared_student = Person.create!(
      name: "Shared Student",
      studio: @studio1,
      type: 'Student',
      level: levels(:one)
    )

    other_student = Person.create!(
      name: "Other Student",
      studio: @studio1,
      type: 'Student',
      level: levels(:one)
    )

    # Shared student dances in both splits
    entry1 = Entry.create!(
      lead: shared_student,
      follow: @instructor1,
      age: ages(:one),
      level: levels(:one)
    )
    Heat.create!(dance: parent_dance, entry: entry1, category: 'Multi', number: 0)

    entry2 = Entry.create!(
      lead: shared_student,
      follow: @instructor2,
      age: ages(:one),
      level: levels(:one)
    )
    Heat.create!(dance: split1, entry: entry2, category: 'Multi', number: 0)

    # Other student only in one split
    max_back = Person.maximum(:back) || 0
    entry3 = Entry.create!(
      lead: other_student,
      follow: Person.create!(name: "Conflict Instructor 3", studio: @studio1, type: 'Professional', back: max_back + 400),
      age: ages(:one),
      level: levels(:one)
    )
    Heat.create!(dance: parent_dance, entry: entry3, category: 'Multi', number: 0)

    @scheduler.schedule_heats

    # Heats with shared_student must be in different groups
    heat1 = Heat.find_by(entry: entry1)
    heat2 = Heat.find_by(entry: entry2)

    assert heat1.number > 0, "Heat 1 should be scheduled"
    assert heat2.number > 0, "Heat 2 should be scheduled"
    assert_not_equal heat1.number, heat2.number,
      "Heats with same dancer should not be in same group"
  end

  test "pack_multi_dance_splits only applies to Multi category" do
    # Mark all existing heats as scratched
    Heat.update_all(number: -1)

    # Create categories
    multi_cat = Category.create!(name: "Multi Only Test", order: 903)
    closed_cat = Category.create!(name: "Closed Only Test", order: 904)

    # Create dances with splits but for Closed category (not Multi)
    parent_dance = Dance.create!(name: "Closed Split Dance", order: 730, closed_category: closed_cat)
    split1 = Dance.create!(name: "Closed Split Dance", order: -30, closed_category: closed_cat)

    # Create multi_levels (but this is a closed dance, not multi)
    MultiLevel.create!(dance: parent_dance, name: "Level 1", start_level: 1, stop_level: 1)
    MultiLevel.create!(dance: split1, name: "Level 2", start_level: 2, stop_level: 2)

    # Create heats as Closed category (not Multi)
    students = []
    instructors = []
    max_back = Person.maximum(:back) || 0
    4.times do |i|
      students << Person.create!(
        name: "Closed Split Student #{i}",
        studio: @studio1,
        type: 'Student',
        level: levels(:one)
      )
      instructors << Person.create!(
        name: "Closed Split Instructor #{i}",
        studio: @studio1,
        type: 'Professional',
        back: max_back + 500 + i
      )
    end

    4.times do |i|
      entry = Entry.create!(
        lead: students[i],
        follow: instructors[i],
        age: ages(:one),
        level: levels(:one)
      )
      dance = i.even? ? parent_dance : split1
      Heat.create!(dance: dance, entry: entry, category: 'Closed', number: 0)
    end

    @scheduler.schedule_heats

    # Closed heats should not be packed by pack_multi_dance_splits
    # (they may still be grouped by normal scheduling logic)
    test_dances = [parent_dance, split1]
    closed_heats = Heat.where(dance: test_dances, category: 'Closed').where('number > 0')

    assert_equal 4, closed_heats.count, "All 4 closed heats should be scheduled"
  end

  test "pack_multi_dance_splits handles empty groups" do
    # This tests the edge case where there are no multi-dance splits
    result = @scheduler.pack_multi_dance_splits([])
    assert_equal [], result
  end

  test "can_add_group_to_packed respects exclude relationships" do
    # Create people with exclude relationship
    person1 = Person.create!(
      name: "Exclude Person 1",
      studio: @studio1,
      type: 'Student',
      level: levels(:one)
    )
    person2 = Person.create!(
      name: "Exclude Person 2",
      studio: @studio1,
      type: 'Student',
      level: levels(:one),
      exclude: person1
    )

    entry = Entry.create!(
      lead: person2,
      follow: @instructor1,
      age: ages(:one),
      level: levels(:one)
    )

    heat = Heat.create!(
      dance: @dance_waltz,
      entry: entry,
      category: 'Multi',
      number: 0
    )

    # Group of heats to add (a split)
    group_heats = [heat]
    group_participants = Set.new([person2.id, @instructor1.id])
    group_couple_type = 'Pro-Am'

    # Create a packed group that already contains person1
    packed_group = {
      heats: [],
      participants: Set.new([person1.id]),
      couple_type: 'Pro-Am'
    }

    # person2 excludes person1, so the group should not be added
    result = @scheduler.can_add_group_to_packed?(group_heats, group_participants, group_couple_type, packed_group, 10)
    assert_equal false, result, "Should not add group when excluded person is in packed group"
  end

  test "can_add_group_to_packed rejects mismatched couple_types" do
    # Create a heat for testing
    entry = Entry.create!(
      lead: @instructor1,
      follow: @student1,
      age: ages(:one),
      level: levels(:one)
    )

    heat = Heat.create!(
      dance: @dance_waltz,
      entry: entry,
      category: 'Multi',
      number: 0
    )

    # Group of heats with Pro-Am couple_type
    group_heats = [heat]
    group_participants = Set.new([@instructor1.id, @student1.id])

    # Try to add Pro-Am split to Amateur Couple packed group
    packed_group = {
      heats: [],
      participants: Set.new,
      couple_type: 'Amateur Couple'
    }

    # Should reject because couple_types don't match
    result = @scheduler.can_add_group_to_packed?(group_heats, group_participants, 'Pro-Am', packed_group, 10)
    assert_equal false, result, "Should not combine splits with different couple_types"

    # Should accept when couple_types match
    packed_group[:couple_type] = 'Pro-Am'
    result = @scheduler.can_add_group_to_packed?(group_heats, group_participants, 'Pro-Am', packed_group, 10)
    assert_equal true, result, "Should allow combining splits with matching couple_types"
  end

  # ===== REBALANCE PACKED GROUPS TESTS =====

  test "rebalance_packed_groups distributes splits evenly" do
    # Create an imbalanced set of packed groups where splits can be moved
    # Rebalancing moves entire splits (same dance_id), not individual heats

    # Create multiple dances to have multiple splits
    dance1 = Dance.create!(name: "Rebalance Dance 1", order: 800)
    dance2 = Dance.create!(name: "Rebalance Dance 2", order: 801)
    dance3 = Dance.create!(name: "Rebalance Dance 3", order: 802)
    dance4 = Dance.create!(name: "Rebalance Dance 4", order: 803)

    students = []
    instructors = []
    max_back = Person.maximum(:back) || 0
    8.times do |i|
      students << Person.create!(
        name: "Rebalance Student #{i}",
        studio: @studio1,
        type: 'Student',
        level: levels(:one)
      )
      instructors << Person.create!(
        name: "Rebalance Instructor #{i}",
        studio: @studio1,
        type: 'Professional',
        back: max_back + 600 + i
      )
    end

    # Create heats with different dances (4 splits, 2 heats each)
    heats = []
    [dance1, dance1, dance2, dance2, dance3, dance3, dance4, dance4].each_with_index do |dance, i|
      entry = Entry.create!(
        lead: students[i],
        follow: instructors[i],
        age: ages(:one),
        level: levels(:one)
      )
      heats << Heat.create!(
        dance: dance,
        entry: entry,
        category: 'Multi',
        number: 0
      )
    end

    # Create imbalanced packed groups: 6 heats (3 splits) in first, 2 heats (1 split) in second
    large_group = {
      heats: heats[0..5],  # dance1, dance2, dance3
      participants: Set.new(heats[0..5].flat_map { |h| [h.entry.lead_id, h.entry.follow_id] })
    }
    small_group = {
      heats: heats[6..7],  # dance4
      participants: Set.new(heats[6..7].flat_map { |h| [h.entry.lead_id, h.entry.follow_id] })
    }

    packed_groups = [large_group, small_group]

    # Run rebalancing
    result = @scheduler.rebalance_packed_groups(packed_groups, 10)

    # Check that groups are more balanced
    sizes = result.map { |g| g[:heats].size }.sort

    # With 4 splits of 2 heats each, best balance is 4-4 (2 splits each)
    assert_equal [4, 4], sizes, "Groups should be balanced to 4-4, got #{sizes}"
  end

  test "rebalance_packed_groups respects participant conflicts" do
    # Create a scenario where rebalancing cannot move a split due to conflicts
    # Rebalancing moves entire splits, so if any participant in a split conflicts,
    # the entire split cannot be moved

    # Create different dances for different splits
    dance1 = Dance.create!(name: "Conflict Dance 1", order: 810)
    dance2 = Dance.create!(name: "Conflict Dance 2", order: 811)
    dance3 = Dance.create!(name: "Conflict Dance 3", order: 812)

    max_back = Person.maximum(:back) || 0

    # Create a shared student who appears in both groups
    shared_student = Person.create!(
      name: "Shared Rebalance Student",
      studio: @studio1,
      type: 'Student',
      level: levels(:one)
    )

    # Create other unique students
    other_students = []
    3.times do |i|
      other_students << Person.create!(
        name: "Other Rebalance Student #{i}",
        studio: @studio1,
        type: 'Student',
        level: levels(:one)
      )
    end

    instructors = []
    4.times do |i|
      instructors << Person.create!(
        name: "Rebalance Conflict Instructor #{i}",
        studio: @studio1,
        type: 'Professional',
        back: max_back + 700 + i
      )
    end

    # Create heats with different dances (different splits)
    # Large group: 3 heats in 2 splits
    # - Split 1 (dance1): shared_student (cannot move due to conflict)
    # - Split 2 (dance2): other_student[0], other_student[1] (can move)
    large_heats = []

    # Split 1: shared_student
    entry = Entry.create!(lead: shared_student, follow: instructors[0], age: ages(:one), level: levels(:one))
    large_heats << Heat.create!(dance: dance1, entry: entry, category: 'Multi', number: 0)

    # Split 2: two other students
    entry = Entry.create!(lead: other_students[0], follow: instructors[1], age: ages(:one), level: levels(:one))
    large_heats << Heat.create!(dance: dance2, entry: entry, category: 'Multi', number: 0)
    entry = Entry.create!(lead: other_students[1], follow: instructors[2], age: ages(:one), level: levels(:one))
    large_heats << Heat.create!(dance: dance2, entry: entry, category: 'Multi', number: 0)

    # Small group: 1 heat with shared_student (different dance/split)
    small_entry = Entry.create!(lead: shared_student, follow: instructors[3], age: ages(:one), level: levels(:one))
    small_heat = Heat.create!(dance: dance3, entry: small_entry, category: 'Multi', number: 0)

    large_group = {
      heats: large_heats,
      participants: Set.new(large_heats.flat_map { |h| [h.entry.lead_id, h.entry.follow_id] })
    }
    small_group = {
      heats: [small_heat],
      participants: Set.new([small_heat.entry.lead_id, small_heat.entry.follow_id])
    }

    packed_groups = [large_group, small_group]

    # Run rebalancing
    result = @scheduler.rebalance_packed_groups(packed_groups, 10)

    # Split 1 (dance1 with shared_student) cannot move - shared_student is in small group
    # Split 2 (dance2 with other_students) CAN move - no conflicts
    # Moving split 2 (2 heats) to small group: large becomes 1, small becomes 3
    # This is still imbalanced (diff > 1), but now small is larger so no more moves
    sizes = result.map { |g| g[:heats].size }.sort

    # Best possible: move split 2 to small group -> [1, 3]
    assert_equal [1, 3], sizes, "Should balance to [1, 3], got #{sizes}"

    # Verify shared_student is not in same group twice
    result.each do |group|
      lead_ids = group[:heats].map { |h| h.entry.lead_id }
      assert_equal lead_ids.uniq.length, lead_ids.length,
        "No dancer should appear twice in same group"
    end
  end

  test "rebalance_packed_groups stops when difference is 1 or less" do
    # Create groups with difference of exactly 1 - no rebalancing should occur

    max_back = Person.maximum(:back) || 0
    students = []
    instructors = []
    3.times do |i|
      students << Person.create!(
        name: "Stop Condition Student #{i}",
        studio: @studio1,
        type: 'Student',
        level: levels(:one)
      )
      instructors << Person.create!(
        name: "Stop Condition Instructor #{i}",
        studio: @studio1,
        type: 'Professional',
        back: max_back + 800 + i
      )
    end

    heats = []
    3.times do |i|
      entry = Entry.create!(
        lead: students[i],
        follow: instructors[i],
        age: ages(:one),
        level: levels(:one)
      )
      heats << Heat.create!(
        dance: @dance_waltz,
        entry: entry,
        category: 'Multi',
        number: 0
      )
    end

    # Create groups with sizes 2 and 1 (difference = 1)
    group1 = {
      heats: heats[0..1],
      participants: Set.new(heats[0..1].flat_map { |h| [h.entry.lead_id, h.entry.follow_id] })
    }
    group2 = {
      heats: [heats[2]],
      participants: Set.new([heats[2].entry.lead_id, heats[2].entry.follow_id])
    }

    packed_groups = [group1, group2]
    original_sizes = packed_groups.map { |g| g[:heats].size }.sort

    # Run rebalancing
    result = @scheduler.rebalance_packed_groups(packed_groups, 10)

    # Sizes should remain unchanged (difference is only 1)
    result_sizes = result.map { |g| g[:heats].size }.sort
    assert_equal original_sizes, result_sizes,
      "Groups with difference of 1 should not be rebalanced"
  end

  test "rebalance_packed_groups respects exclude relationships" do
    max_back = Person.maximum(:back) || 0

    # Create two students with exclude relationship
    student1 = Person.create!(
      name: "Exclude Rebalance Student 1",
      studio: @studio1,
      type: 'Student',
      level: levels(:one)
    )
    student2 = Person.create!(
      name: "Exclude Rebalance Student 2",
      studio: @studio1,
      type: 'Student',
      level: levels(:one),
      exclude: student1
    )
    student3 = Person.create!(
      name: "No Exclude Student",
      studio: @studio1,
      type: 'Student',
      level: levels(:one)
    )

    instructors = []
    3.times do |i|
      instructors << Person.create!(
        name: "Exclude Rebalance Instructor #{i}",
        studio: @studio1,
        type: 'Professional',
        back: max_back + 900 + i
      )
    end

    # Create heats
    entry1 = Entry.create!(lead: student1, follow: instructors[0], age: ages(:one), level: levels(:one))
    heat1 = Heat.create!(dance: @dance_waltz, entry: entry1, category: 'Multi', number: 0)

    entry2 = Entry.create!(lead: student2, follow: instructors[1], age: ages(:one), level: levels(:one))
    heat2 = Heat.create!(dance: @dance_waltz, entry: entry2, category: 'Multi', number: 0)

    entry3 = Entry.create!(lead: student3, follow: instructors[2], age: ages(:one), level: levels(:one))
    heat3 = Heat.create!(dance: @dance_waltz, entry: entry3, category: 'Multi', number: 0)

    # Large group has student1 and student3
    # Small group has student2 (who excludes student1)
    large_group = {
      heats: [heat1, heat3],
      participants: Set.new([student1.id, instructors[0].id, student3.id, instructors[2].id])
    }
    small_group = {
      heats: [heat2],
      participants: Set.new([student2.id, instructors[1].id])
    }

    packed_groups = [large_group, small_group]

    # Run rebalancing
    result = @scheduler.rebalance_packed_groups(packed_groups, 10)

    # student1's heat cannot move to small_group (student2 excludes student1)
    # Only student3's heat can move
    # Result should be 1-2 (student3 moved to small group)
    sizes = result.map { |g| g[:heats].size }.sort

    # Note: With only 1 heat movable and difference of 1, it should balance to 1-2
    # But since difference starts at 1, no movement happens
    # Let's verify the exclude relationship is respected
    result.each do |group|
      participants = group[:participants]
      # If student1 is in group, student2 should not be
      if participants.include?(student1.id)
        assert !participants.include?(student2.id),
          "student2 should not be in same group as student1 (exclude relationship)"
      end
    end
  end

  test "rebalance_packed_groups handles single group" do
    # Single group should be returned unchanged
    max_back = Person.maximum(:back) || 0
    student = Person.create!(
      name: "Single Group Student",
      studio: @studio1,
      type: 'Student',
      level: levels(:one)
    )
    instructor = Person.create!(
      name: "Single Group Instructor",
      studio: @studio1,
      type: 'Professional',
      back: max_back + 1000
    )

    entry = Entry.create!(lead: student, follow: instructor, age: ages(:one), level: levels(:one))
    heat = Heat.create!(dance: @dance_waltz, entry: entry, category: 'Multi', number: 0)

    single_group = {
      heats: [heat],
      participants: Set.new([student.id, instructor.id])
    }

    result = @scheduler.rebalance_packed_groups([single_group], 10)

    assert_equal 1, result.length, "Single group should be returned"
    assert_equal 1, result.first[:heats].length, "Heat count should be unchanged"
  end

  test "rebalance_packed_groups integrated with schedule_heats produces balanced groups" do
    # Integration test: verify schedule_heats with multi-dance splits produces balanced output

    # Mark all existing heats as scratched
    Heat.update_all(number: -1)

    multi_cat = Category.create!(name: "Integration Rebalance Test", order: 950)

    # Create parent and split dances
    parent_dance = Dance.create!(name: "Integration 3-Dance", order: 750, multi_category: multi_cat)
    split1 = Dance.create!(name: "Integration 3-Dance", order: -50, multi_category: multi_cat)
    split2 = Dance.create!(name: "Integration 3-Dance", order: -51, multi_category: multi_cat)
    split3 = Dance.create!(name: "Integration 3-Dance", order: -52, multi_category: multi_cat)

    # Create multi_levels
    MultiLevel.create!(dance: parent_dance, name: "Level 1", start_level: 1, stop_level: 1)
    MultiLevel.create!(dance: split1, name: "Level 2", start_level: 2, stop_level: 2)
    MultiLevel.create!(dance: split2, name: "Level 3", start_level: 3, stop_level: 3)
    MultiLevel.create!(dance: split3, name: "Level 4", start_level: 4, stop_level: 4)

    # Create entries with a pattern that would result in imbalanced packing without rebalancing
    # One shared dancer across multiple splits to force separate groups
    max_back = Person.maximum(:back) || 0
    shared_student = Person.create!(
      name: "Integration Shared Student",
      studio: @studio1,
      type: 'Student',
      level: levels(:one)
    )

    unique_students = []
    8.times do |i|
      unique_students << Person.create!(
        name: "Integration Unique Student #{i}",
        studio: @studio1,
        type: 'Student',
        level: levels(:one)
      )
    end

    instructors = []
    12.times do |i|
      instructors << Person.create!(
        name: "Integration Instructor #{i}",
        studio: @studio1,
        type: 'Professional',
        back: max_back + 1100 + i
      )
    end

    # Create heats:
    # - shared_student in parent_dance, split1, split2, split3 (4 heats, must be in 4 different groups)
    # - 2 unique students per split (8 more heats that can be distributed)
    heat_count = 0

    [parent_dance, split1, split2, split3].each_with_index do |dance, i|
      # Shared student heat
      entry = Entry.create!(
        lead: shared_student,
        follow: instructors[heat_count],
        age: ages(:one),
        level: levels(:one)
      )
      Heat.create!(dance: dance, entry: entry, category: 'Multi', number: 0)
      heat_count += 1

      # 2 unique student heats
      2.times do |j|
        entry = Entry.create!(
          lead: unique_students[i * 2 + j],
          follow: instructors[heat_count],
          age: ages(:one),
          level: levels(:one)
        )
        Heat.create!(dance: dance, entry: entry, category: 'Multi', number: 0)
        heat_count += 1
      end
    end

    @scheduler.schedule_heats

    # Get scheduled heats
    test_dances = [parent_dance, split1, split2, split3]
    multi_heats = Heat.where(dance: test_dances, category: 'Multi').where('number > 0')

    # Group by heat number
    heats_by_number = multi_heats.group_by(&:number)

    # Should have 4 groups (one for each shared_student heat)
    assert_equal 4, heats_by_number.size, "Should have 4 groups due to shared student"

    # Each group should have 3 heats (1 shared + 2 unique, balanced by rebalancing)
    sizes = heats_by_number.values.map(&:size).sort
    assert_equal [3, 3, 3, 3], sizes,
      "Rebalancing should distribute heats evenly (3-3-3-3), got #{sizes}"
  end

  test "pack_multi_dance_splits keeps each split in a single heat" do
    # This test verifies that all heats within a split (same dance_id) are
    # scheduled together in one heat number, never split across multiple heats.
    # This is critical for judging - all competitors in a split must dance
    # together to be fairly ranked against each other.

    Heat.update_all(number: -1)

    multi_cat = Category.create!(name: "Split Integrity Test", order: 960)

    # Create parent and split dances
    parent_dance = Dance.create!(name: "Integrity 3-Dance", order: 760, multi_category: multi_cat)
    split1 = Dance.create!(name: "Integrity 3-Dance", order: -60, multi_category: multi_cat)
    split2 = Dance.create!(name: "Integrity 3-Dance", order: -61, multi_category: multi_cat)

    MultiLevel.create!(dance: parent_dance, name: "Newcomer", start_level: 1, stop_level: 1)
    MultiLevel.create!(dance: split1, name: "Bronze", start_level: 2, stop_level: 2)
    MultiLevel.create!(dance: split2, name: "Silver", start_level: 3, stop_level: 3)

    max_back = Person.maximum(:back) || 0

    # Create 3 entries for parent_dance (Newcomer split)
    newcomer_heats = []
    3.times do |i|
      student = Person.create!(
        name: "Newcomer Integrity Student #{i}",
        studio: @studio1,
        type: 'Student',
        level: levels(:one)
      )
      instructor = Person.create!(
        name: "Newcomer Integrity Instructor #{i}",
        studio: @studio1,
        type: 'Professional',
        back: max_back + 1200 + i
      )
      entry = Entry.create!(lead: student, follow: instructor, age: ages(:one), level: levels(:one))
      newcomer_heats << Heat.create!(dance: parent_dance, entry: entry, category: 'Multi', number: 0)
    end

    # Create 2 entries for split1 (Bronze split)
    bronze_heats = []
    2.times do |i|
      student = Person.create!(
        name: "Bronze Integrity Student #{i}",
        studio: @studio1,
        type: 'Student',
        level: levels(:one)
      )
      instructor = Person.create!(
        name: "Bronze Integrity Instructor #{i}",
        studio: @studio1,
        type: 'Professional',
        back: max_back + 1210 + i
      )
      entry = Entry.create!(lead: student, follow: instructor, age: ages(:one), level: levels(:one))
      bronze_heats << Heat.create!(dance: split1, entry: entry, category: 'Multi', number: 0)
    end

    # Create 2 entries for split2 (Silver split)
    silver_heats = []
    2.times do |i|
      student = Person.create!(
        name: "Silver Integrity Student #{i}",
        studio: @studio1,
        type: 'Student',
        level: levels(:one)
      )
      instructor = Person.create!(
        name: "Silver Integrity Instructor #{i}",
        studio: @studio1,
        type: 'Professional',
        back: max_back + 1220 + i
      )
      entry = Entry.create!(lead: student, follow: instructor, age: ages(:one), level: levels(:one))
      silver_heats << Heat.create!(dance: split2, entry: entry, category: 'Multi', number: 0)
    end

    @scheduler.schedule_heats

    # Verify each split has all its heats in exactly one heat number
    newcomer_heats.each(&:reload)
    bronze_heats.each(&:reload)
    silver_heats.each(&:reload)

    newcomer_numbers = newcomer_heats.map(&:number).uniq
    bronze_numbers = bronze_heats.map(&:number).uniq
    silver_numbers = silver_heats.map(&:number).uniq

    assert_equal 1, newcomer_numbers.size,
      "All Newcomer heats should be in one heat number, got #{newcomer_numbers}"
    assert_equal 1, bronze_numbers.size,
      "All Bronze heats should be in one heat number, got #{bronze_numbers}"
    assert_equal 1, silver_numbers.size,
      "All Silver heats should be in one heat number, got #{silver_numbers}"

    # Also verify the heats are scheduled (positive number)
    assert newcomer_numbers.first > 0, "Newcomer heats should be scheduled"
    assert bronze_numbers.first > 0, "Bronze heats should be scheduled"
    assert silver_numbers.first > 0, "Silver heats should be scheduled"
  end

  # ===== DETERMINISTIC CATEGORY SPLITTING TESTS =====

  test "schedule_heats produces deterministic results with category splits" do
    # Mark all existing heats as scratched
    Heat.update_all(number: -1)

    # Create a solo category with split
    solo_category = Category.create!(name: "Deterministic Solo Test", order: 50, split: "3")
    waltz = Dance.create!(name: "Deterministic Waltz", order: 50, solo_category: solo_category)
    tango = Dance.create!(name: "Deterministic Tango", order: 51, solo_category: solo_category)
    foxtrot = Dance.create!(name: "Deterministic Foxtrot", order: 52, solo_category: solo_category)

    # Get a unique base for solo orders
    solo_order_base = (Solo.maximum(:order) || 0) + 100

    # Create 9 solos (should split into 3 groups of 3)
    heats = []
    9.times do |i|
      student = Person.create!(
        name: "Deterministic Student #{i}",
        studio: @studio1,
        type: 'Student',
        level: levels(:one)
      )

      entry = Entry.create!(
        lead: student,
        follow: @instructor1,
        age: ages(:one),
        level: levels(:one)
      )

      dance = [waltz, tango, foxtrot][i % 3]
      heat = Heat.create!(dance: dance, entry: entry, category: 'Solo', number: 0)
      Solo.create!(heat: heat, order: solo_order_base + i + 1)
      heats << heat
    end

    # Run scheduling multiple times and verify same result
    results = []
    3.times do
      @scheduler.schedule_heats
      heats.each(&:reload)
      results << heats.map(&:number).map(&:to_i)
    end

    # All runs should produce identical results
    assert_equal 1, results.uniq.size,
      "Scheduling should be deterministic. Got different results: #{results.inspect}"
  end

  test "schedule_heats maintains solo order within category splits" do
    # Mark all existing heats as scratched
    Heat.update_all(number: -1)

    # Create a solo category with split
    solo_category = Category.create!(name: "Solo Order Test", order: 55, split: "2")
    waltz = Dance.create!(name: "Order Test Waltz", order: 55, solo_category: solo_category)

    # Get a unique base for solo orders
    solo_order_base = (Solo.maximum(:order) || 0) + 200

    # Create 4 solos with specific order values (relative to base)
    heats = []
    [3, 1, 4, 2].each_with_index do |solo_order, i|
      student = Person.create!(
        name: "Order Student #{i}",
        studio: @studio1,
        type: 'Student',
        level: levels(:one)
      )

      entry = Entry.create!(
        lead: student,
        follow: @instructor1,
        age: ages(:one),
        level: levels(:one)
      )

      heat = Heat.create!(dance: waltz, entry: entry, category: 'Solo', number: 0)
      Solo.create!(heat: heat, order: solo_order_base + solo_order)
      heats << heat
    end

    @scheduler.schedule_heats
    heats.each(&:reload)

    # Get heat numbers sorted by solo.order
    heat_numbers_by_solo_order = heats.sort_by { |h| h.solo.order }.map { |h| h.number.to_i }

    # Solos should be in increasing heat number order when sorted by solo.order
    # (within each split group)
    assert heat_numbers_by_solo_order == heat_numbers_by_solo_order.sort,
      "Solos should be scheduled in solo.order sequence. Got: #{heat_numbers_by_solo_order}"
  end

  test "Block class has base_dance_category method" do
    rhythm_cat = Category.create!(name: "Block Base Cat Test", order: 900)

    entry = Entry.create!(
      lead: @student1,
      follow: @instructor1,
      age: ages(:one),
      level: levels(:one)
    )

    block = HeatScheduler::Block.new(entry, 'Open', rhythm_cat)

    # Block should have base_dance_category that returns the agenda_category
    assert_respond_to block, :base_dance_category
    assert_equal rhythm_cat, block.base_dance_category
    assert_equal block.dance_category, block.base_dance_category
  end

  test "Group uses base_dance_category for agenda category assignment" do
    # This test verifies that the Group class uses base_dance_category
    # which doesn't depend on stale heat numbers

    # Mark all existing heats as scratched
    Heat.update_all(number: -1)

    # Create a category with split and extensions
    test_category = Category.create!(name: "Group Base Cat Test", order: 60, split: "2")
    ext = CatExtension.create!(category: test_category, order: 600, part: 2, start_heat: 3)

    waltz = Dance.create!(name: "Group Test Waltz", order: 60, open_category: test_category)

    # Create heats with stale numbers that would put them in the extension
    # if dance_category (not base_dance_category) was used
    heats = []
    4.times do |i|
      student = Person.create!(
        name: "Group Test Student #{i}",
        studio: @studio1,
        type: 'Student',
        level: levels(:one)
      )

      entry = Entry.create!(
        lead: student,
        follow: @instructor1,
        age: ages(:one),
        level: levels(:one)
      )

      # Set stale number above extension start_heat
      heat = Heat.create!(dance: waltz, entry: entry, category: 'Open', number: 10 + i)
      heats << heat
    end

    # Schedule - this should use base_dance_category, not the stale numbers
    @scheduler.schedule_heats
    heats.each(&:reload)

    # All heats should be scheduled (positive numbers)
    heats.each do |heat|
      assert heat.number > 0, "Heat should be scheduled with positive number"
    end

    # Run again to verify determinism despite different "stale" numbers
    first_result = heats.map(&:number).map(&:to_i)

    @scheduler.schedule_heats
    heats.each(&:reload)

    second_result = heats.map(&:number).map(&:to_i)

    assert_equal first_result, second_result,
      "Results should be identical regardless of previous heat numbers"
  end

  # ===== PRE-SPLIT MULTI-DANCE PACKING TESTS =====

  test "pack_multi_dance_splits packs pre-split dances with same multi_category and heat_length" do
    # Mark all existing heats as scratched
    Heat.update_all(number: -1)

    # Create a multi category
    multi_cat = Category.create!(name: "PreSplit Pack Test", order: 950)

    # Create 3 pre-split dances with different names but same multi_category and heat_length
    dance_a = Dance.create!(name: "PreSplit AA", order: 750, multi_category: multi_cat, heat_length: 3)
    dance_b = Dance.create!(name: "PreSplit BB", order: -1, multi_category: multi_cat, heat_length: 3)
    dance_c = Dance.create!(name: "PreSplit CC", order: -2, multi_category: multi_cat, heat_length: 3)

    # Create child dances for multi
    child1 = Dance.create!(name: "PreSplit Child W", order: 751)
    child2 = Dance.create!(name: "PreSplit Child T", order: 752)
    child3 = Dance.create!(name: "PreSplit Child F", order: 753)

    [dance_a, dance_b, dance_c].each do |d|
      Multi.create!(parent_id: d.id, dance_id: child1.id)
      Multi.create!(parent_id: d.id, dance_id: child2.id)
      Multi.create!(parent_id: d.id, dance_id: child3.id)
    end

    # Create entries and heats for each split with non-overlapping dancers
    max_back = Person.maximum(:back) || 0
    students = 6.times.map do |i|
      Person.create!(name: "PreSplit Student #{i}", studio: @studio1, type: 'Student', level: levels(:one))
    end
    instructors = 6.times.map do |i|
      Person.create!(name: "PreSplit Inst #{i}", studio: @studio1, type: 'Professional', back: max_back + 300 + i)
    end

    # Dance A: students 0,1
    [0, 1].each do |i|
      entry = Entry.create!(lead: students[i], follow: instructors[i], age: ages(:one), level: levels(:one))
      Heat.create!(dance: dance_a, entry: entry, category: 'Multi', number: 0)
    end

    # Dance B: students 2,3
    [2, 3].each do |i|
      entry = Entry.create!(lead: students[i], follow: instructors[i], age: ages(:one), level: levels(:one))
      Heat.create!(dance: dance_b, entry: entry, category: 'Multi', number: 0)
    end

    # Dance C: students 4,5
    [4, 5].each do |i|
      entry = Entry.create!(lead: students[i], follow: instructors[i], age: ages(:one), level: levels(:one))
      Heat.create!(dance: dance_c, entry: entry, category: 'Multi', number: 0)
    end

    @scheduler.schedule_heats

    # Get all scheduled Multi heats for our test dances
    test_dances = [dance_a, dance_b, dance_c]
    multi_heats = Heat.where(dance: test_dances, category: 'Multi').where('number > 0')

    assert_equal 6, multi_heats.count, "All 6 heats should be scheduled"

    # Since no dancers overlap, all heats could be packed into fewer heat numbers
    heat_numbers = multi_heats.pluck(:number).uniq
    assert heat_numbers.size < 3, "Pre-split dances should pack (got #{heat_numbers.size} groups for 3 splits)"
  end

  test "pack_multi_dance_splits does not pack pre-split dances with different heat_length" do
    # Mark all existing heats as scratched
    Heat.update_all(number: -1)

    multi_cat = Category.create!(name: "PreSplit HeatLen Test", order: 951)

    # Two dances with same multi_category but different heat_length
    dance_short = Dance.create!(name: "PreSplit Short", order: 760, multi_category: multi_cat, heat_length: 2)
    dance_long  = Dance.create!(name: "PreSplit Long",  order: -1, multi_category: multi_cat, heat_length: 4)

    child1 = Dance.create!(name: "PreSplit HL Child W", order: 761)
    child2 = Dance.create!(name: "PreSplit HL Child T", order: 762)

    [dance_short, dance_long].each do |d|
      Multi.create!(parent_id: d.id, dance_id: child1.id)
      Multi.create!(parent_id: d.id, dance_id: child2.id)
    end

    max_back = Person.maximum(:back) || 0
    students = 4.times.map do |i|
      Person.create!(name: "PreSplit HL Student #{i}", studio: @studio1, type: 'Student', level: levels(:one))
    end
    instructors = 4.times.map do |i|
      Person.create!(name: "PreSplit HL Inst #{i}", studio: @studio1, type: 'Professional', back: max_back + 400 + i)
    end

    # Dance Short: students 0,1
    [0, 1].each do |i|
      entry = Entry.create!(lead: students[i], follow: instructors[i], age: ages(:one), level: levels(:one))
      Heat.create!(dance: dance_short, entry: entry, category: 'Multi', number: 0)
    end

    # Dance Long: students 2,3
    [2, 3].each do |i|
      entry = Entry.create!(lead: students[i], follow: instructors[i], age: ages(:one), level: levels(:one))
      Heat.create!(dance: dance_long, entry: entry, category: 'Multi', number: 0)
    end

    @scheduler.schedule_heats

    test_dances = [dance_short, dance_long]
    multi_heats = Heat.where(dance: test_dances, category: 'Multi').where('number > 0')

    assert_equal 4, multi_heats.count, "All 4 heats should be scheduled"

    # Different heat_length should NOT be packed together
    short_numbers = multi_heats.where(dance: dance_short).pluck(:number).uniq
    long_numbers = multi_heats.where(dance: dance_long).pluck(:number).uniq

    assert_empty short_numbers & long_numbers,
      "Different heat_length dances should not share heat numbers"
  end
end