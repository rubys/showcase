require "test_helper"

class DanceLimitCalculatorTest < ActiveSupport::TestCase
  class TestClass
    include DanceLimitCalculator
  end

  setup do
    @test_class = TestClass
    @event = events(:one)
    @dance = dances(:waltz)
    @student = people(:student_one)
    @instructor = people(:instructor_one)
  end

  test "combined_categories? returns true when heat_range_cat is 1" do
    @event.update!(heat_range_cat: 1)
    assert @test_class.combined_categories?
  end

  test "combined_categories? returns false when heat_range_cat is not 1" do
    @event.update!(heat_range_cat: 0)
    assert_not @test_class.combined_categories?
  end

  test "effective_category returns Open/Closed when combined and category is Open or Closed" do
    @event.update!(heat_range_cat: 1)
    assert_equal "Open/Closed", @test_class.effective_category("Open")
    assert_equal "Open/Closed", @test_class.effective_category("Closed")
  end

  test "effective_category returns original category when not combined" do
    @event.update!(heat_range_cat: 0)
    assert_equal "Open", @test_class.effective_category("Open")
    assert_equal "Closed", @test_class.effective_category("Closed")
    assert_equal "Multi", @test_class.effective_category("Multi")
  end

  test "effective_category returns non-Open/Closed categories unchanged even when combined" do
    @event.update!(heat_range_cat: 1)
    assert_equal "Multi", @test_class.effective_category("Multi")
    assert_equal "Solo", @test_class.effective_category("Solo")
  end

  test "calculate_heat_counts_for_person returns correct counts" do
    # Create test data using existing fixtures
    entry = entries(:one)
    heat1 = Heat.create!(entry: entry, dance: @dance, category: "Open", number: 1)
    heat2 = Heat.create!(entry: entry, dance: @dance, category: "Open", number: 2)
    heat3 = Heat.create!(entry: entry, dance: @dance, category: "Closed", number: 3)

    # Test for Arthur (the lead in the entry)
    arthur = people(:Arthur)
    counts = @test_class.calculate_heat_counts_for_person(arthur.id, @dance.id)

    assert_equal 2, counts[:lead_counts]["Open"]
    assert_equal 1, counts[:lead_counts]["Closed"]
    assert counts[:follow_counts].empty? || counts[:follow_counts].values.all?(&:zero?)
  end

  test "calculate_heat_counts_for_person excludes specified entry" do
    entry1 = entries(:student_instructor_bronze_closed)
    entry2 = Entry.create!(
      lead: @student,
      follow: people(:bertha_instructor),
      age: ages(:age1),
      level: levels(:bronze)
    )

    Heat.create!(entry: entry1, dance: @dance, category: "Open", number: 1)
    Heat.create!(entry: entry2, dance: @dance, category: "Open", number: 2)

    counts_without_exclusion = @test_class.calculate_heat_counts_for_person(@student.id, @dance.id)
    counts_with_exclusion = @test_class.calculate_heat_counts_for_person(@student.id, @dance.id, exclude_entry_id: entry2.id)

    assert counts_without_exclusion[:lead_counts]["Open"] > counts_with_exclusion[:lead_counts]["Open"]
  end

  test "check_limit_violation returns nil when under limit" do
    @event.update!(dance_limit: 10)
    @dance.update!(limit: nil)

    violation = @test_class.check_limit_violation(@student.id, @dance, "Open", additional_heats: 1)
    assert_nil violation
  end

  test "check_limit_violation returns violation details when over limit" do
    @event.update!(dance_limit: 2)
    @dance.update!(limit: nil)

    # Create existing heats
    entry = entries(:student_instructor_bronze_closed)
    Heat.create!(entry: entry, dance: @dance, category: "Open", number: 1)
    Heat.create!(entry: entry, dance: @dance, category: "Open", number: 2)

    violation = @test_class.check_limit_violation(@student.id, @dance, "Open", additional_heats: 1)

    assert_not_nil violation
    assert_equal @student.id, violation[:person_id]
    assert_equal @dance.name, violation[:dance]
    assert_equal "Open", violation[:category]
    assert_equal 2, violation[:current_count]
    assert_equal 1, violation[:additional_heats]
    assert_equal 3, violation[:total_count]
    assert_equal 2, violation[:limit]
    assert_equal 1, violation[:excess]
  end

  test "check_limit_violation uses dance-specific limit when available" do
    @event.update!(dance_limit: 5)
    @dance.update!(limit: 3)

    entry = entries(:student_instructor_bronze_closed)
    Heat.create!(entry: entry, dance: @dance, category: "Open", number: 1)
    Heat.create!(entry: entry, dance: @dance, category: "Open", number: 2)
    Heat.create!(entry: entry, dance: @dance, category: "Open", number: 3)

    violation = @test_class.check_limit_violation(@student.id, @dance, "Open", additional_heats: 1)

    assert_not_nil violation
    assert_equal 3, violation[:limit], "Should use dance-specific limit, not event limit"
  end

  test "people_with_heats_for_dance returns correct data structure" do
    entry = entries(:student_instructor_bronze_closed)
    Heat.create!(entry: entry, dance: @dance, category: "Open", number: 1)
    Heat.create!(entry: entry, dance: @dance, category: "Closed", number: 2)

    people_data = @test_class.people_with_heats_for_dance(@dance)

    assert people_data.is_a?(Array)
    assert people_data.any? { |data| data[:person].id == @student.id }

    student_data = people_data.find { |data| data[:person].id == @student.id }
    assert_not_nil student_data
    assert student_data.key?(:total_count)
    assert student_data.key?(:lead_count)
    assert student_data.key?(:follow_count)
    assert student_data.key?(:category)
  end

  test "people_with_heats_for_dance combines Open/Closed when heat_range_cat is 1" do
    @event.update!(heat_range_cat: 1)

    entry = entries(:student_instructor_bronze_closed)
    Heat.create!(entry: entry, dance: @dance, category: "Open", number: 1)
    Heat.create!(entry: entry, dance: @dance, category: "Closed", number: 2)

    people_data = @test_class.people_with_heats_for_dance(@dance)
    student_data = people_data.find { |data| data[:person].id == @student.id }

    assert_equal "Open/Closed", student_data[:category]
    assert_equal 2, student_data[:total_count]
  end

  test "people_with_heats_for_dance keeps categories separate when heat_range_cat is 0" do
    @event.update!(heat_range_cat: 0)

    entry = entries(:student_instructor_bronze_closed)
    Heat.create!(entry: entry, dance: @dance, category: "Open", number: 1)
    Heat.create!(entry: entry, dance: @dance, category: "Closed", number: 2)

    people_data = @test_class.people_with_heats_for_dance(@dance)

    open_data = people_data.find { |data| data[:person].id == @student.id && data[:category] == "Open" }
    closed_data = people_data.find { |data| data[:person].id == @student.id && data[:category] == "Closed" }

    assert_not_nil open_data
    assert_not_nil closed_data
    assert_equal 1, open_data[:total_count]
    assert_equal 1, closed_data[:total_count]
  end

  test "find_all_violations returns empty array when no violations" do
    @event.update!(dance_limit: 100)

    violations = @test_class.find_all_violations
    assert_equal [], violations
  end

  test "find_all_violations finds violations across all dances" do
    @event.update!(dance_limit: 1)

    entry = entries(:student_instructor_bronze_closed)
    Heat.create!(entry: entry, dance: @dance, category: "Open", number: 1)
    Heat.create!(entry: entry, dance: @dance, category: "Open", number: 2)

    violations = @test_class.find_all_violations

    assert violations.any?
    violation = violations.first
    assert_equal @student.name, violation[:person]
    assert_equal @dance.name, violation[:dance]
    assert violation[:count] > violation[:limit]
  end

  test "batch_load_heat_counts efficiently loads counts for multiple people and dances" do
    entry1 = entries(:student_instructor_bronze_closed)
    entry2 = entries(:couple_bronze_closed)

    Heat.create!(entry: entry1, dance: @dance, category: "Open", number: 1)
    Heat.create!(entry: entry2, dance: @dance, category: "Closed", number: 2)

    person_ids = [entry1.lead_id, entry1.follow_id, entry2.lead_id, entry2.follow_id]
    dance_ids = [@dance.id]

    counts = @test_class.batch_load_heat_counts(person_ids, dance_ids)

    assert counts.is_a?(Hash)
    assert counts.key?(entry1.lead_id)
    assert counts[entry1.lead_id][@dance.id][:lead]["Open"] > 0
  end
end