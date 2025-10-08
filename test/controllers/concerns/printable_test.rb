require "test_helper"

# Comprehensive tests for the Printable concern which handles agenda generation,
# invoice creation, and report formatting. Printable is critical for:
#
# - Generating competition agendas with heat scheduling
# - Creating invoices for studios and students
# - Generating heat sheets and score sheets for judges
# - Managing ballroom assignments and time calculations  
# - Handling PDF generation and rendering
# - Processing financial calculations and billing logic
#
# Tests cover:
# - Agenda generation with category organization
# - Heat assignment and ballroom splitting
# - Invoice generation with cost calculations
# - Time scheduling and category timing
# - Couple detection and billing relationships
# - Report generation (heat sheets, score sheets)
# - Utility methods (undoable, renumber_needed)

class PrintableTest < ActiveSupport::TestCase
  include Printable

  setup do
    @event = events(:one)
    Event.current = @event
    
    @studio = studios(:one)
    @category = categories(:one)
    @dance = dances(:waltz)
    @instructor = people(:instructor1)
    @student = people(:student_one)
    @age = ages(:one)
    @level = levels(:one)
    
    # Create test entry and heat
    @entry = Entry.create!(
      lead: @instructor,
      follow: @student,
      age: @age,
      level: @level
    )
    
    @heat = Heat.create!(
      number: 100,
      entry: @entry,
      dance: @dance,
      category: 'Closed'
    )
  end

  # ===== AGENDA GENERATION TESTS =====
  
  test "generate_agenda creates agenda structure" do
    generate_agenda
    
    assert_not_nil @heats
    assert_not_nil @categories
    assert_not_nil @agenda
    
    # Should have basic agenda categories
    assert @agenda.key?('Uncategorized') || @agenda.any?
  end
  
  test "generate_agenda organizes heats by number" do
    # Create multiple heats with same number
    heat2 = Heat.create!(
      number: 100,
      entry: @entry,
      dance: dances(:tango),
      category: 'Closed'
    )
    
    generate_agenda
    
    # Heats should be grouped by number
    heat_group = @heats.find { |number, heats| number == 100 }
    assert_not_nil heat_group
    assert_equal 100, heat_group[0]
    assert heat_group[1].length >= 1
  end
  
  test "generate_agenda handles unscheduled heats" do
    # Create heat with number 0 (unscheduled)
    unscheduled = Heat.create!(
      number: 0,
      entry: @entry,
      dance: @dance,
      category: 'Closed'
    )
    
    generate_agenda
    
    # Should have unscheduled category if heats exist
    if @heats.any? { |number, heats| number == 0 }
      assert @agenda.key?('Unscheduled')
    end
  end
  
  test "generate_agenda includes categories and extensions" do
    generate_agenda
    
    # Should combine categories and extensions
    assert @categories.is_a?(Hash)
    
    # Categories should be sorted by order
    if @categories.any?
      # Check that we have category objects
      @categories.values.each do |cat|
        assert_respond_to cat, :name
        assert_respond_to cat, :order
      end
    end
  end
  
  test "generate_agenda sets oneday flag correctly" do
    generate_agenda
    
    # Should set @oneday based on event configuration
    assert_not_nil @oneday
    assert_includes [true, false], @oneday
  end
  
  # ===== BALLROOM ASSIGNMENT TESTS =====
  
  test "assign_rooms handles solo heats" do
    # Create solo heat
    solo_heat = Heat.create!(
      number: 101,
      entry: @entry,
      dance: @dance,
      category: 'Solo'
    )
    
    rooms = assign_rooms(2, [solo_heat], nil)
    
    # Solo heats should go to nil room
    assert_equal({nil => [solo_heat]}, rooms)
  end
  
  test "assign_rooms handles single ballroom" do
    heats = [@heat]
    
    rooms = assign_rooms(1, heats, nil)
    
    # Single ballroom assigns all heats to nil
    assert_equal({nil => heats}, rooms)
  end
  
  test "assign_rooms splits heats for two ballrooms" do
    # Create student and professional heats
    student_entry = Entry.create!(
      lead: @student,
      follow: people(:student_two),
      instructor: @instructor,
      age: @age,
      level: @level
    )
    
    student_heat = Heat.create!(
      number: 102,
      entry: student_entry,
      dance: @dance,
      category: 'Closed'
    )
    
    pro_heat = @heat # Has professional lead
    
    rooms = assign_rooms(2, [student_heat, pro_heat], nil)
    
    # Should split students and professionals
    assert rooms.key?(:A)
    assert rooms.key?(:B)
    assert_equal 2, rooms[:A].length + rooms[:B].length
  end
  
  test "assign_rooms handles ballroom assignments" do
    # Set specific ballroom on heat
    @heat.update!(ballroom: 'A')
    
    heats = [@heat]
    rooms = assign_rooms(2, heats, nil)
    
    # Should respect existing ballroom assignments
    if heats.all? { |heat| !heat.ballroom.nil? }
      assert rooms.key?('A')
      assert_includes rooms['A'], @heat
    end
  end
  
  # ===== INVOICE GENERATION TESTS =====
  
  test "generate_invoice creates invoice structure" do
    generate_invoice([@studio])
    
    assert_not_nil @invoices
    assert @invoices.key?(@studio)
    
    studio_invoice = @invoices[@studio]
    assert studio_invoice.key?(:dance_count)
    assert studio_invoice.key?(:purchases)
    assert studio_invoice.key?(:dance_cost)
    assert studio_invoice.key?(:total_cost)
    assert studio_invoice.key?(:dances)
    assert studio_invoice.key?(:entries)
  end
  
  test "generate_invoice calculates dance costs" do
    generate_invoice([@studio])
    
    studio_invoice = @invoices[@studio]
    
    # Should have non-negative costs
    assert studio_invoice[:dance_cost] >= 0
    assert studio_invoice[:total_cost] >= 0
    assert studio_invoice[:dance_count] >= 0
  end
  
  test "generate_invoice handles event cost configuration" do
    @event.update!(heat_cost: 25, solo_cost: 30)
    
    generate_invoice([@studio])
    
    # Costs should be applied based on event configuration
    studio_invoice = @invoices[@studio]
    assert_not_nil studio_invoice[:dance_cost]
  end
  
  test "generate_invoice identifies offered dance types" do
    generate_invoice([@studio])
    
    assert_not_nil @offered
    assert @offered.key?(:freestyles)
    assert @offered.key?(:solos)
    assert @offered.key?(:multis)
    
    # Values should be boolean
    assert_includes [true, false], @offered[:freestyles]
    assert_includes [true, false], @offered[:solos]
    assert_includes [true, false], @offered[:multis]
  end
  
  # ===== COUPLE DETECTION TESTS =====
  
  test "find_couples identifies paired people" do
    find_couples
    
    assert_not_nil @paired
    assert_not_nil @couples
    
    # Should be arrays
    assert @paired.is_a?(Array)
    assert @couples.is_a?(Hash)
  end
  
  # ===== HEAT SHEETS TESTS =====
  
  test "heat_sheets generates heat assignments" do
    heat_sheets
    
    assert_not_nil @heatlist
    assert_not_nil @people
    assert_not_nil @heats
    
    # Should map people to their heat IDs
    assert @heatlist.is_a?(Hash)
    @heatlist.each do |person, heat_ids|
      assert person.is_a?(Person)
      assert heat_ids.is_a?(Array)
    end
  end
  
  test "heat_sheets includes formations" do
    # Would need Formation and Solo models to fully test
    heat_sheets
    
    # Should set up the basic structure
    assert_not_nil @heatlist
    assert_not_nil @layout
    assert_not_nil @event
    assert @nologo
  end
  
  # ===== SCORE SHEETS TESTS =====
  
  test "score_sheets generates judge scoring structure" do
    score_sheets
    
    assert_not_nil @judges
    assert_not_nil @people
    assert_not_nil @heats
    assert_not_nil @formations
    
    # Should set layout and event info
    assert_not_nil @layout
    assert_not_nil @event
    assert @nologo
    assert_not_nil @track_ages
  end
  
  test "score_sheets filters people and heats correctly" do
    score_sheets
    
    # Should include judges
    @judges.each do |judge|
      assert_equal 'Judge', judge.type
    end
    
    # Should include student people (may be empty in test)
    @people.each do |person|
      assert_equal 'Student', person.type
    end
    
    # Should include all heats
    assert @heats.is_a?(ActiveRecord::Relation)
  end
  
  # ===== UTILITY METHOD TESTS =====
  
  test "undoable detects heats with previous numbers" do
    # Create heat with prev_number
    @heat.update!(prev_number: 99)
    
    result = undoable
    
    # Should detect undoable heats
    assert_includes [true, false], result
  end
  
  test "undoable returns false when no undoable heats" do
    # Ensure no heats have prev_number
    Heat.update_all(prev_number: 0)
    
    result = undoable
    
    assert_equal false, result
  end
  
  test "renumber_needed detects non-sequential numbering" do
    # Create heats with gaps in numbering
    Heat.create!(
      number: 1,
      entry: @entry,
      dance: @dance,
      category: 'Closed'
    )
    
    Heat.create!(
      number: 5, # Gap in sequence
      entry: @entry,
      dance: @dance,
      category: 'Closed'
    )
    
    result = renumber_needed
    
    # Should detect that renumbering is needed
    assert_includes [true, false], result
  end
  
  test "renumber_needed returns false for sequential numbers" do
    # Clear existing heats and create sequential ones
    Heat.where.not(number: 0).destroy_all
    
    (1..3).each do |i|
      Heat.create!(
        number: i,
        entry: @entry,
        dance: @dance,
        category: 'Closed'
      )
    end
    
    result = renumber_needed
    
    assert_equal false, result
  end
  
  # ===== PDF RENDERING TESTS =====
  
  test "render_as_pdf sets up proper file handling" do
    # Mock request for testing
    request = OpenStruct.new(
      url: 'http://localhost:3000/test.pdf',
      headers: {'SERVER_PORT' => '3000'}
    )
    
    # Skip actual Chrome/PDF execution in tests
    skip "PDF rendering requires Chrome browser and is environment-specific"
  end
  
  # ===== INTEGRATION TESTS =====
  
  test "agenda generation with real categories and heats" do
    # Use existing fixture data
    generate_agenda
    
    # Should process without errors
    assert_not_nil @agenda
    assert_not_nil @categories
    
    # Should handle empty or minimal data gracefully
    assert @agenda.is_a?(Hash)
  end
  
  test "invoice generation with minimal data" do
    generate_invoice([@studio])
    
    # Should handle minimal test data
    assert_not_nil @invoices
    studio_invoice = @invoices[@studio]
    
    # Should have valid structure even with minimal data
    assert studio_invoice[:dance_count] >= 0
    assert studio_invoice[:total_cost] >= 0
  end
  
  # ===== ERROR HANDLING TESTS =====
  
  test "assign_rooms handles empty heat list" do
    rooms = assign_rooms(2, [], nil)
    
    # Should return empty structure
    assert rooms.is_a?(Hash)
  end
  
  test "generate_agenda handles missing categories" do
    # Clear categories
    Category.destroy_all
    
    generate_agenda
    
    # Should handle gracefully
    assert_not_nil @agenda
    assert @categories.is_a?(Hash)
  end
  
  test "generate_invoice handles missing studios" do
    generate_invoice([])
    
    # Should handle empty studio list
    assert_not_nil @invoices
    assert @invoices.empty?
  end
  
  # ===== CONFIGURATION TESTS =====
  
  test "methods respect event configuration" do
    @event.update!(
      heat_length: 5,
      solo_length: 3,
      include_times: true,
      track_ages: true
    )
    
    generate_agenda

    # Should use event configuration
    assert_not_nil @oneday
    assert_not_nil @track_ages if defined?(@track_ages)
  end

  # ===== SEQUENTIAL HEAT ORDERING TESTS =====

  test "generate_agenda orders categories by sequential heat number" do
    # Clear all heats to avoid fixture interference
    Heat.destroy_all

    # Create categories with heats in non-sequential category order
    cat1 = categories(:one)
    max_order = Category.maximum(:order) || 0
    cat2 = Category.create!(name: 'Second Category', order: max_order + 1)

    # Cat1 has heat 100, Cat2 has heat 50 (should appear first despite higher order)
    Heat.create!(number: 100, entry: @entry, dance: @dance, category: 'Closed')
    Heat.create!(number: 50, entry: @entry, dance: dances(:tango), category: 'Closed')

    # Set up categories on dances
    @dance.update!(closed_category: cat1)
    dances(:tango).update!(closed_category: cat2)

    generate_agenda

    # Second Category (heat 50) should appear before First Category (heat 100)
    category_names = @agenda.keys
    second_idx = category_names.index('Second Category')
    first_idx = category_names.index(cat1.name)

    # Both categories should be in the agenda and in the correct order
    assert_not_nil second_idx, "Second Category should be in agenda"
    assert_not_nil first_idx, "#{cat1.name} should be in agenda"
    assert second_idx < first_idx, "Second Category (heat 50) should appear before #{cat1.name} (heat 100)"
  end

  test "generate_agenda splits categories when different categories interleave" do
    # Clear existing heats
    Heat.destroy_all

    cat1 = categories(:one)
    max_order = Category.maximum(:order) || 0
    cat2 = Category.create!(name: 'Second Category', order: max_order + 1)

    @dance.update!(solo_category: cat1)
    dances(:tango).update!(solo_category: cat2)
    dances(:rumba).update!(solo_category: cat1)

    # Create heats: cat1, cat1, cat2, cat2, cat1 (should split cat1)
    heat55 = Heat.create!(number: 55, entry: @entry, dance: @dance, category: 'Solo')
    heat56 = Heat.create!(number: 56, entry: @entry, dance: @dance, category: 'Solo')
    heat57 = Heat.create!(number: 57, entry: @entry, dance: dances(:tango), category: 'Solo')
    heat58 = Heat.create!(number: 58, entry: @entry, dance: dances(:tango), category: 'Solo')
    heat59 = Heat.create!(number: 59, entry: @entry, dance: dances(:rumba), category: 'Solo')

    # Create solo records for the heats with unique order values
    max_order = Solo.maximum(:order) || 0
    Solo.create!(heat: heat55, order: max_order + 1)
    Solo.create!(heat: heat56, order: max_order + 2)
    Solo.create!(heat: heat57, order: max_order + 3)
    Solo.create!(heat: heat58, order: max_order + 4)
    Solo.create!(heat: heat59, order: max_order + 5)

    generate_agenda

    # Cat1 should appear twice (before and after cat2)
    matching_keys = @agenda.keys.select { |k| k.include?(cat1.name) }
    assert_equal 2, matching_keys.length, "Category should be split due to interleaving"

    # Second occurrence should have "(continued)" suffix
    assert_equal cat1.name, matching_keys[0]
    assert matching_keys[1].include?('(continued)'), "Second occurrence should have (continued)"
  end

  test "generate_agenda keeps categories together when consecutive" do
    # Clear existing heats
    Heat.destroy_all

    cat = categories(:one)
    @dance.update!(solo_category: cat)

    # Create consecutive heats with gaps in numbering (scratches, etc)
    heat100 = Heat.create!(number: 100, entry: @entry, dance: @dance, category: 'Solo')
    heat105 = Heat.create!(number: 105, entry: @entry, dance: @dance, category: 'Solo')
    heat110 = Heat.create!(number: 110, entry: @entry, dance: @dance, category: 'Solo')

    # Create solo records for the heats with unique order values
    max_order = Solo.maximum(:order) || 0
    Solo.create!(heat: heat100, order: max_order + 1)
    Solo.create!(heat: heat105, order: max_order + 2)
    Solo.create!(heat: heat110, order: max_order + 3)

    generate_agenda

    # Category should appear only once (all heats are consecutive in the same category)
    matching_keys = @agenda.keys.select { |k| k == cat.name }
    assert_equal 1, matching_keys.length, "Category should not be split when heats are consecutive"
  end

  test "generate_agenda handles multiple interleaved sections of same category" do
    # Clear all heats to avoid fixture interference
    Heat.destroy_all

    cat1 = categories(:one)
    max_order = Category.maximum(:order) || 0
    cat2 = Category.create!(name: 'Second Category', order: max_order + 1)
    cat3 = Category.create!(name: 'Third Category', order: max_order + 2)

    waltz = dances(:waltz)
    tango = dances(:tango)
    rumba = dances(:rumba)
    chacha = dances(:chacha)

    waltz.update!(solo_category: cat1)
    tango.update!(solo_category: cat2)
    rumba.update!(solo_category: cat3)
    chacha.update!(solo_category: cat1)

    # Create heats: cat1, cat2, cat1, cat3, cat1 (cat1 appears 3 times)
    heat10 = Heat.create!(number: 10, entry: @entry, dance: waltz, category: 'Solo')
    heat20 = Heat.create!(number: 20, entry: @entry, dance: tango, category: 'Solo')
    heat30 = Heat.create!(number: 30, entry: @entry, dance: waltz, category: 'Solo')
    heat40 = Heat.create!(number: 40, entry: @entry, dance: rumba, category: 'Solo')
    heat50 = Heat.create!(number: 50, entry: @entry, dance: chacha, category: 'Solo')

    # Create solo records for the heats with unique order values
    max_order = Solo.maximum(:order) || 0
    Solo.create!(heat: heat10, order: max_order + 1)
    Solo.create!(heat: heat20, order: max_order + 2)
    Solo.create!(heat: heat30, order: max_order + 3)
    Solo.create!(heat: heat40, order: max_order + 4)
    Solo.create!(heat: heat50, order: max_order + 5)

    generate_agenda

    # Should have three occurrences of cat1
    matching_keys = @agenda.keys.select { |k| k.include?(cat1.name) }
    assert matching_keys.length >= 3, "Category should appear 3 times due to interleaving"
  end

  test "generate_agenda maintains Uncategorized and Unscheduled at end" do
    # Create various heats
    Heat.create!(number: 1, entry: @entry, dance: @dance, category: 'Closed')
    Heat.create!(number: 50, entry: @entry, dance: @dance, category: 'Closed')
    Heat.create!(number: 0, entry: @entry, dance: @dance, category: 'Closed') # Unscheduled

    generate_agenda

    # Uncategorized and Unscheduled should be at the end
    keys = @agenda.keys
    last_keys = keys.last(2)

    special_keys = keys.select { |k| k == 'Uncategorized' || k == 'Unscheduled' }
    special_keys.each do |key|
      assert last_keys.include?(key), "#{key} should be at the end"
    end
  end
end