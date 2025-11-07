require "test_helper"

class EventTest < ActiveSupport::TestCase
  setup do
    @event = events(:one)
    Event.current = @event
  end

  # ===== PARTNERLESS ENTRIES TESTS =====

  test "should create Nobody person when partnerless_entries is enabled" do
    # Ensure Nobody doesn't exist initially
    Person.find_by(id: 0)&.destroy

    # Create a level if none exist
    unless Level.any?
      Level.create!(id: 1, name: 'Test Level')
    end

    @event.update!(partnerless_entries: true)

    assert Person.exists?(0), "Nobody person should be created"
    nobody = Person.find(0)
    assert_equal 'Nobody', nobody.name
    assert_equal 'Student', nobody.type
    assert_equal 0, nobody.back
    assert_not_nil nobody.studio
    assert_not_nil nobody.level
  end

  test "should not create Nobody person when partnerless_entries is disabled" do
    # Ensure Nobody doesn't exist initially
    Person.find_by(id: 0)&.destroy

    @event.update!(partnerless_entries: false)

    assert_not Person.exists?(0), "Nobody person should not be created when feature is disabled"
  end

  test "should not create duplicate Nobody person if it already exists" do
    # Create Nobody manually
    unless Level.any?
      Level.create!(id: 1, name: 'Test Level')
    end

    event_staff = Studio.find_or_create_by(name: 'Event Staff') { |s| s.tables = 0 }
    Person.create!(
      id: 0,
      name: 'Nobody',
      type: 'Student',
      studio: event_staff,
      level: Level.first,
      back: 0
    )

    initial_count = Person.where(id: 0).count
    assert_equal 1, initial_count

    # Enable partnerless entries
    @event.update!(partnerless_entries: false)
    @event.update!(partnerless_entries: true)

    # Should still only have one Nobody
    final_count = Person.where(id: 0).count
    assert_equal 1, final_count
  end

  test "should create Event Staff studio if it doesn't exist" do
    # Remove Event Staff studio if it exists
    Studio.find_by(name: 'Event Staff')&.destroy

    # Ensure Nobody doesn't exist
    Person.find_by(id: 0)&.destroy

    # Create a level if none exist
    unless Level.any?
      Level.create!(id: 1, name: 'Test Level')
    end

    @event.update!(partnerless_entries: true)

    event_staff = Studio.find_by(name: 'Event Staff')
    assert_not_nil event_staff, "Event Staff studio should be created"
    assert_equal 0, event_staff.tables

    nobody = Person.find(0)
    assert_equal event_staff, nobody.studio
  end

  test "should only trigger on change from false to true" do
    # Ensure Nobody doesn't exist initially
    Person.find_by(id: 0)&.destroy

    # Create a level if none exist
    unless Level.any?
      Level.create!(id: 1, name: 'Test Level')
    end

    # Set to true initially
    @event.update!(partnerless_entries: true)
    assert Person.exists?(0), "Nobody should be created on first enable"

    # Delete Nobody
    Person.find(0).destroy

    # Update event with partnerless_entries still true (no change)
    @event.update!(name: 'Changed Name')
    assert_not Person.exists?(0), "Nobody should not be recreated when setting doesn't change"

    # Now disable and re-enable
    @event.update!(partnerless_entries: false)
    assert_not Person.exists?(0)

    @event.update!(partnerless_entries: true)
    assert Person.exists?(0), "Nobody should be created when changed from false to true"
  end
end
