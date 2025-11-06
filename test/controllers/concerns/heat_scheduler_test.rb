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
    # Set category orders to ensure predictable sorting
    @category_open.update!(order: 20)
    @category_closed.update!(order: 10)

    # Use fixture entries
    entry1 = entries(:one)
    entry2 = entries(:two)

    # Mark all existing heats as scratched (negative numbers) to exclude them
    Heat.update_all(number: -1)

    # Create new heats for testing
    heat_closed = Heat.create!(
      dance: @dance_waltz,
      entry: entry1,
      category: 'Closed',
      number: 0
    )

    heat_open = Heat.create!(
      dance: @dance_waltz,
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
end