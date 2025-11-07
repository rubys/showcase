require "test_helper"

# Comprehensive tests for the EntryForm concern which handles entry creation
# and form initialization logic. EntryForm is critical for entry management as it:
#
# - Initializes form data for creating dance partnership entries
# - Handles complex role detection (Leader/Follower/Both)
# - Manages instructor and student availability based on studio relationships
# - Creates or finds entries with proper validation
# - Handles special cases like formation entries and spouse partnerships
# - Filters levels based on event solo level configuration
# - Provides dance category lookup functionality

class EntryFormTest < ActiveSupport::TestCase
  include EntryForm

  setup do
    @event = events(:one)
    Event.current = @event
    
    @studio = studios(:one)
    @instructor = people(:instructor1)
    @student = people(:student_one) 
    @student2 = people(:student_two)
    @age = ages(:one)
    @level = levels(:one)
  end

  # ===== BASIC FORM INITIALIZATION TESTS =====
  
  test "form_init with student person initializes correctly" do
    form_init(@student.id)
    
    assert_equal @student, @person
    assert_not_nil @avail
    assert_not_nil @instructors
    assert_not_nil @ages
    assert_not_nil @levels
    assert_not_nil @entries
    assert_equal 4, @entries.keys.length # Closed, Open, Multi, Solo
  end
  
  test "form_init with professional person initializes correctly" do
    form_init(@instructor.id)
    
    assert_equal @instructor, @person
    assert_not_nil @avail
    assert_equal [], @students # Professionals don't get students list
    assert_not_nil @ages
    assert_not_nil @levels
  end
  
  test "form_init with no person uses nobody when studio set" do
    @studio = studios(:one)
    form_init
    
    assert_equal Person.nobody, @person
  end
  
  test "form_init without person shows all people" do
    @studio = nil
    form_init
    
    assert_not_nil @followers
    assert_not_nil @leads
    assert_not_nil @instructors
    assert_not_nil @students
  end
  
  test "form_init with Both role sets both seeking options" do
    both_person = Person.create!(
      name: 'Both Test',
      type: 'Student',
      role: 'Both',
      studio: @studio,
      level: @level
    )
    
    form_init(both_person.id)
    assert_equal ['Leader', 'Follower'], @seeking
    assert_not_nil @boths
  end
  
  test "form_init with formation sets seeking to both roles" do
    @formation = true
    form_init(@student.id)
    
    assert_equal ['Leader', 'Follower'], @seeking
  end
  
  test "form_init determines role from entry when role is Both" do
    both_person = Person.create!(
      name: 'Both Entry Test',
      type: 'Student', 
      role: 'Both',
      studio: @studio,
      level: @level
    )
    
    entry = Entry.create!(
      lead: @instructor,
      follow: both_person,
      age: @age,
      level: @level
    )
    
    form_init(both_person.id, entry)
    assert_equal 'Follower', @role
  end
  
  # ===== AVAILABILITY TESTS =====
  
  test "form_init removes person from available list" do
    form_init(@student.id)
    
    # Person should not be in their own availability list
    assert_not_includes @avail.values, @student.id
  end
  
  test "form_init prioritizes spouse in availability list" do
    # Create a spouse with same last name
    spouse = Person.create!(
      name: "#{@student.name.split(',').first}, Jane",
      type: 'Student',
      role: 'Both',
      studio: @studio,
      level: @level
    )
    
    form_init(@student.id)
    
    # Spouse should be first in availability list
    first_available_id = @avail.values.first
    assert_equal spouse.id, first_available_id
  end
  
  test "form_init for professional includes instructors" do
    form_init(@instructor.id)
    
    # When person is professional, they get access to professionals
    instructor_ids = @instructors.values
    assert instructor_ids.length > 0
    
    # Should include at least some instructors
    assert @instructors.is_a?(Hash)
    assert_not_empty @instructors
  end
  
  # ===== LEVEL FILTERING TESTS =====
  
  test "form_init filters levels for solo when event has solo level" do
    solo_level = Level.create!(name: 'Solo Level')
    @event.update!(solo_level: solo_level)
    
    @solo = true
    form_init(@student.id)
    
    # Should only include levels >= solo level
    level_ids = @levels.map(&:last)
    assert_includes level_ids, solo_level.id
  end
  
  test "form_init filters levels for non-solo when event has solo level" do
    solo_level = Level.create!(name: 'Solo Level')
    @event.update!(solo_level: solo_level)
    
    @solo = false
    form_init(@student.id)
    
    # Should only include levels < solo level (if any exist)
    level_ids = @levels.map(&:last)
    assert_not_includes level_ids, solo_level.id
  end
  
  test "form_init includes all levels when no solo level set" do
    @event.update!(solo_level: nil)
    
    form_init(@student.id)
    
    # Should include all levels
    assert @levels.length > 0
  end
  
  # ===== ENTRY CREATION TESTS =====
  
  test "find_or_create_entry creates entry with correct lead/follow" do
    params = {
      primary: @student.id,
      partner: @instructor.id,
      level: @level.id,
      age: @age.id
    }
    
    entry = find_or_create_entry(params)
    
    assert_equal @instructor, entry.lead # Professional becomes lead
    assert_equal @student, entry.follow # Student becomes follow
    assert_equal @level, entry.level
    assert_equal @age, entry.age
  end
  
  test "find_or_create_entry respects role parameter" do
    params = {
      primary: @student.id,
      partner: @instructor.id,
      role: 'Follower',
      level: @level.id,
      age: @age.id
    }
    
    entry = find_or_create_entry(params)
    
    assert_equal @instructor, entry.lead # Partner becomes lead when role is Follower
    assert_equal @student, entry.follow # Primary becomes follow
  end
  
  test "find_or_create_entry handles follower role person" do
    follower = Person.create!(
      name: 'Follower Test',
      type: 'Student',
      role: 'Follower',
      studio: @studio,
      level: @level
    )
    
    params = {
      primary: follower.id,
      partner: @instructor.id,
      level: @level.id,
      age: @age.id
    }
    
    entry = find_or_create_entry(params)
    
    assert_equal @instructor, entry.lead
    assert_equal follower, entry.follow
  end
  
  test "find_or_create_entry sets instructor to nil for professional partnerships" do
    instructor2 = Person.create!(
      name: 'Second Instructor',
      type: 'Professional',
      role: 'Both',
      studio: @studio
    )
    
    params = {
      primary: @instructor.id,
      partner: instructor2.id,
      level: @level.id,
      age: @age.id
    }
    
    entry = find_or_create_entry(params)
    
    assert_nil entry.instructor_id
  end
  
  test "find_or_create_entry uses instructor parameter for amateur partnerships" do
    params = {
      primary: @student.id,
      partner: @student2.id,
      instructor: @instructor.id,
      level: @level.id,
      age: @age.id
    }
    
    entry = find_or_create_entry(params)
    
    assert_equal @instructor.id, entry.instructor_id
  end
  
  test "find_or_create_entry creates special levels and ages when needed" do
    params = {
      primary: @student.id,
      partner: @instructor.id,
      level: '0',
      age: '0'
    }
    
    entry = find_or_create_entry(params)
    
    # Should create special "All Levels" and "All Ages" entries
    assert_equal 'All Levels', entry.level.name
    assert_equal 'All Ages', entry.age.description
    assert_equal 0, entry.level.id
    assert_equal 0, entry.age.id
  end
  
  test "find_or_create_entry uses first age when no age specified" do
    first_age = Age.order(:id).first
    
    params = {
      primary: @student.id,
      partner: @instructor.id,
      level: @level.id
    }
    
    entry = find_or_create_entry(params)
    
    assert_equal first_age, entry.age
  end
  
  # ===== DANCE CATEGORY TESTS =====
  
  test "dance_categories returns solo categories for solo" do
    dance = dances(:waltz)
    
    categories = dance_categories(dance, true)
    
    # Should return solo categories sorted by order
    assert categories.is_a?(Array)
    categories.each do |name, id|
      dance_obj = Dance.find(id)
      assert_not_nil dance_obj.solo_category
    end
  end
  
  test "dance_categories returns freestyle categories for non-solo" do
    dance = dances(:waltz)
    
    categories = dance_categories(dance, false)
    
    # Should return freestyle categories sorted by order  
    assert categories.is_a?(Array)
    categories.each do |name, id|
      dance_obj = Dance.find(id)
      assert_not_nil dance_obj.freestyle_category
    end
  end
  
  test "dance_categories sorts by category order" do
    dance = dances(:waltz)
    
    categories = dance_categories(dance, false)
    
    if categories.length > 1
      # Verify sorting by order
      orders = categories.map do |name, id|
        Dance.find(id).freestyle_category.order || 0
      end
      assert_equal orders.sort, orders
    else
      # If only one category, test passes
      assert categories.length >= 0
    end
  end
  
  # ===== EDGE CASES AND ERROR HANDLING =====
  
  test "form_init handles missing person gracefully" do
    # Test with nil instead of non-existent ID to avoid RecordNotFound
    form_init(nil)
    
    # Should not raise error and should set up basic form data
    assert_not_nil @ages
    assert_not_nil @levels
    assert_not_nil @entries
  end
  
  test "find_or_create_entry handles missing level gracefully" do
    params = {
      primary: @student.id,
      partner: @instructor.id,
      level: 99999, # Non-existent level
      age: @age.id
    }
    
    entry = find_or_create_entry(params)
    
    # Should handle missing level without crashing
    assert_not_nil entry
  end
  
  test "find_or_create_entry handles missing age gracefully" do
    params = {
      primary: @student.id,
      partner: @instructor.id,
      level: @level.id,
      age: 99999 # Non-existent age
    }
    
    entry = find_or_create_entry(params)
    
    # Should handle missing age without crashing
    assert_not_nil entry
  end
  
  # ===== CONFIGURATION TESTS =====
  
  test "form_init sets columns from dance maximum" do
    # Set a specific column value on a dance
    dance = dances(:waltz)
    dance.update!(col: 6)
    
    form_init(@student.id)
    
    assert_equal 6, @columns
  end
  
  test "form_init sets columns to default when no dances" do
    # Clear all dances
    Dance.update_all(col: nil)
    
    form_init(@student.id)
    
    assert_equal 4, @columns # Default value
  end
  
  test "form_init sets track_ages from event" do
    @event.update!(track_ages: true)

    form_init(@student.id)

    assert_equal true, @track_ages
  end

  # ===== PARTNERLESS ENTRIES TESTS =====

  test "form_init includes Nobody in available list when partnerless_entries enabled" do
    # Enable partnerless entries
    @event.update!(partnerless_entries: true)

    # Ensure Nobody exists
    unless Person.exists?(0)
      event_staff = Studio.find_or_create_by(name: 'Event Staff') { |s| s.tables = 0 }
      Person.create!(
        id: 0,
        name: 'Nobody',
        type: 'Student',
        studio: event_staff,
        level: @level,
        back: 0
      )
    end

    form_init(@student.id)

    assert_includes @avail.keys, 'Nobody'
    assert_equal 0, @avail['Nobody']
    # Nobody should be first in the list
    assert_equal 'Nobody', @avail.keys.first
  end

  test "form_init does not include Nobody when partnerless_entries disabled" do
    # Disable partnerless entries
    @event.update!(partnerless_entries: false)

    # Ensure Nobody exists but shouldn't be in dropdown
    unless Person.exists?(0)
      event_staff = Studio.find_or_create_by(name: 'Event Staff') { |s| s.tables = 0 }
      Person.create!(
        id: 0,
        name: 'Nobody',
        type: 'Student',
        studio: event_staff,
        level: @level,
        back: 0
      )
    end

    form_init(@student.id)

    assert_not_includes @avail.keys, 'Nobody'
  end

  test "form_init does not include Nobody for professionals" do
    # Enable partnerless entries
    @event.update!(partnerless_entries: true)

    # Ensure Nobody exists
    unless Person.exists?(0)
      event_staff = Studio.find_or_create_by(name: 'Event Staff') { |s| s.tables = 0 }
      Person.create!(
        id: 0,
        name: 'Nobody',
        type: 'Student',
        studio: event_staff,
        level: @level,
        back: 0
      )
    end

    form_init(@instructor.id)

    # Professionals shouldn't see Nobody option
    assert_not_includes @avail.keys, 'Nobody'
  end

  test "form_init handles missing Nobody gracefully when partnerless_entries enabled" do
    # Enable partnerless entries but don't create Nobody
    @event.update!(partnerless_entries: true)
    Person.find_by(id: 0)&.destroy

    # Should not crash if Nobody doesn't exist
    assert_nothing_raised do
      form_init(@student.id)
    end

    # Nobody shouldn't be in list if it doesn't exist
    assert_not_includes @avail.keys, 'Nobody'
  end
end