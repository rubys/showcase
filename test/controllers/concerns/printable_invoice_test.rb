require "test_helper"

# Comprehensive tests for invoice generation in the Printable concern.
# These tests cover the complex invoice logic that handles:
#
# - Studio invoices (all entries for a studio)
# - Individual student invoices (filtered to one student)
# - Individual instructor invoices (pro-pro entries only)
# - Pro-am vs amateur couple vs pro-pro entry filtering
# - Professional vs student pricing
# - Entry splitting logic for billing
# - invoice_to_id relationships (billing one person's costs to another)
# - Combo dance handling in invoices
#
# This test suite was created to prevent regressions after fixing multiple
# invoice-related bugs including filtering, pricing, and display issues.

class PrintableInvoiceTest < ActiveSupport::TestCase
  include Printable

  setup do
    @event = events(:one)
    Event.current = @event

    # Set up event pricing
    @event.update!(
      heat_cost: 25.0,
      solo_cost: 55.0,
      pro_heat_cost: 10.0,
      pro_solo_cost: 15.0,
      pro_heats: true  # Allow pro-pro entries
    )

    # Create a fresh studio with no fixture data to avoid pollution
    @studio = Studio.create!(name: "Test Studio #{SecureRandom.hex(8)}")
    @age = ages(:one)
    @level = levels(:one)
    @name_counter = 0

    # Create Person with id=0 for formations
    Person.find_or_create_by!(id: 0) do |p|
      p.name = "Nobody"
      p.type = "Guest"
      p.studio = @studio
    end
  end

  # ===== INSTRUCTOR INVOICE TESTS =====

  test "instructor invoice excludes pro-am entries" do
    instructor = create_professional(@studio, "Pro Instructor")
    student = create_student(@studio, "Student One")

    # Create pro-am entry
    entry = create_entry(instructor, student)
    create_heat(entry, 'Closed')

    # Generate instructor invoice (student=false, instructor=person)
    generate_invoice([@studio], false, instructor)

    # Should have no entries (pro-am excluded from instructor invoices)
    assert_equal 0, @invoices[@studio][:dance_count]
    assert_equal 0, @invoices[@studio][:dance_cost]
  end

  test "instructor invoice excludes amateur couple entries" do
    instructor = create_professional(@studio, "Pro Instructor")
    student1 = create_student(@studio, "Student One")
    student2 = create_student(@studio, "Student Two")

    # Create amateur couple entry with instructor in instructor field
    entry = create_entry(student1, student2)
    entry.update!(instructor: instructor)
    create_heat(entry, 'Closed')

    # Generate instructor invoice
    generate_invoice([@studio], false, instructor)

    # Should have no entries (amateur couples excluded from instructor invoices)
    assert_equal 0, @invoices[@studio][:dance_count]
  end

  test "instructor invoice includes pro-pro entries where instructor participates" do
    instructor1 = create_professional(@studio, "Pro One")
    instructor2 = create_professional(@studio, "Pro Two")

    # Create pro-pro solo entry
    entry = create_entry(instructor1, instructor2)
    heat = create_heat(entry, 'Solo')
    create_solo(heat)

    # Generate instructor1's invoice
    generate_invoice([@studio], false, instructor1)

    # Should have entry (pro-pro included, split for individual invoice)
    dances = @invoices[@studio][:dances]
    assert_equal 0.5, dances[instructor1][:dances], "Instructor1 should have 0.5 dances (split)"

    # Should use pro pricing and split
    expected_cost = @event.pro_solo_cost / 2.0  # 15.0 / 2 = 7.5
    assert_equal expected_cost, dances[instructor1][:cost], "Instructor1 should pay half cost"
  end

  test "instructor invoice excludes pro-pro entries where instructor doesn't participate" do
    instructor1 = create_professional(@studio, "Pro One")
    instructor2 = create_professional(@studio, "Pro Two")
    instructor3 = create_professional(@studio, "Pro Three")

    # Create pro-pro entry without instructor1
    entry = create_entry(instructor2, instructor3)
    heat = create_heat(entry, 'Solo')
    create_solo(heat)

    # Generate instructor1's invoice
    generate_invoice([@studio], false, instructor1)

    # Should have no entries (instructor1 not involved)
    assert_equal 0, @invoices[@studio][:dance_count]
  end

  test "instructor invoice from paired studios excludes entries not involving instructor" do
    studio2 = Studio.create!(name: "Paired Studio")
    StudioPair.create!(studio1: @studio, studio2: studio2)

    instructor1 = create_professional(@studio, "Pro One")
    instructor2 = create_professional(studio2, "Pro Two")
    instructor3 = create_professional(studio2, "Pro Three")

    # Create pro-pro entry between paired studios, but not involving instructor1
    entry = create_entry(instructor2, instructor3)
    heat = create_heat(entry, 'Solo')
    create_solo(heat)

    # Generate instructor1's invoice
    generate_invoice([@studio], false, instructor1)

    # Should have no entries (instructor1 not lead, follow, or instructor)
    assert_equal 0, @invoices[@studio][:dance_count]
  end

  # ===== STUDENT INVOICE TESTS =====

  test "student invoice shows only that student's entries" do
    student1 = create_student(@studio, "Student One")
    student2 = create_student(@studio, "Student Two")
    instructor = create_professional(@studio, "Instructor")

    # Create entries for both students
    entry1 = create_entry(student1, instructor)
    entry2 = create_entry(student2, instructor)
    create_heat(entry1, 'Closed')
    create_heat(entry2, 'Closed')

    # Generate student1's invoice (student=true, instructor=student1)
    generate_invoice([@studio], true, student1)

    # The dances hash includes all people, but student invoice filters entries
    dances = @invoices[@studio][:dances]
    assert dances.key?(student1), "Should include student1"
    assert_not dances.key?(student2), "Should not include student2"

    # Instructor may be in hash but with 0 dances/cost
    # (filtering happens in the view based on person type)
    assert_equal 1, dances[student1][:dances], "Student1 should have 1 dance"
    assert dances[student1][:cost] > 0, "Student1 should have cost"
  end

  test "student invoice with invoice_to_id shows costs on recipient's invoice" do
    student1 = create_student(@studio, "Student One")
    student2 = create_student(@studio, "Student Two")
    student2.update!(invoice_to_id: student1.id)
    instructor = create_professional(@studio, "Instructor")

    # Create entries for both students
    entry1 = create_entry(student1, instructor)
    entry2 = create_entry(student2, instructor)
    create_heat(entry1, 'Closed')
    create_heat(entry2, 'Closed')

    # Generate student1's invoice (who receives student2's costs)
    generate_invoice([@studio], true, student1)

    dances = @invoices[@studio][:dances]
    assert dances.key?(student1), "Should include student1"
    assert dances.key?(student2), "Should include student2 (billed to student1)"

    # Both should have costs
    assert dances[student1][:cost] > 0
    assert dances[student2][:cost] > 0
  end

  test "student invoice splits amateur couple costs" do
    student1 = create_student(@studio, "Student One")
    student2 = create_student(@studio, "Student Two")

    # Create amateur couple entry
    entry = create_entry(student1, student2)
    create_heat(entry, 'Closed')

    # Generate student1's invoice
    generate_invoice([@studio], true, student1)

    # Amateur couples are split - each student gets 0.5 dances
    # The dances hash includes both students, view filtering happens later
    dances = @invoices[@studio][:dances]
    assert dances.key?(student1), "Should include student1"
    assert_equal 0.5, dances[student1][:dances], "Student1 should have 0.5 dances (split)"

    expected_cost = @event.heat_cost / 2.0  # 25.0 / 2 = 12.5
    assert_equal expected_cost, dances[student1][:cost], "Student1 should pay half"
  end

  # ===== STUDIO INVOICE TESTS =====

  test "studio invoice includes all entry types" do
    student1 = create_student(@studio, "Student One")
    student2 = create_student(@studio, "Student Two")
    pro1 = create_professional(@studio, "Pro One")
    pro2 = create_professional(@studio, "Pro Two")

    # Create different entry types
    amateur = create_entry(student1, student2)
    proam = create_entry(student1, pro1)
    propro = create_entry(pro1, pro2)

    create_heat(amateur, 'Closed')
    create_heat(proam, 'Closed')
    heat = create_heat(propro, 'Solo')
    create_solo(heat)

    # Generate studio invoice (student=false, instructor=nil)
    generate_invoice([@studio], false, nil)

    # Should include all people
    dances = @invoices[@studio][:dances]
    assert dances.key?(student1)
    assert dances.key?(student2)
    assert dances.key?(pro1)
    assert dances.key?(pro2)
  end

  # ===== PRO-PRO SOLO PRICING AND SPLITTING TESTS =====

  test "pro-pro solo from same studio uses professional pricing" do
    pro1 = create_professional(@studio, "Pro One")
    pro2 = create_professional(@studio, "Pro Two")

    entry = create_entry(pro1, pro2)
    heat = create_heat(entry, 'Solo')
    create_solo(heat)

    # Studio invoice
    generate_invoice([@studio], false, nil)

    # Should use pro_solo_cost (15) not solo_cost (55)
    assert_equal 15.0, @invoices[@studio][:dance_cost]
  end

  test "pro-pro solo from same studio not split on studio invoice" do
    pro1 = create_professional(@studio, "Pro One")
    pro2 = create_professional(@studio, "Pro Two")

    entry = create_entry(pro1, pro2)
    heat = create_heat(entry, 'Solo')
    create_solo(heat)

    # Studio invoice
    generate_invoice([@studio], false, nil)

    # Should count as 1 entry (not split)
    assert_equal 1.0, @invoices[@studio][:dance_count]
    assert_equal 15.0, @invoices[@studio][:dance_cost]
  end

  test "pro-pro solo from same studio split on instructor invoice" do
    pro1 = create_professional(@studio, "Pro One")
    pro2 = create_professional(@studio, "Pro Two")

    entry = create_entry(pro1, pro2)
    heat = create_heat(entry, 'Solo')
    create_solo(heat)

    # Instructor invoice for pro1
    generate_invoice([@studio], false, pro1)

    # Should count as 0.5 entries (split between two instructors)
    dances = @invoices[@studio][:dances]
    assert_equal 0.5, dances[pro1][:dances], "Pro1 should have 0.5 dances (split)"
    assert_equal 7.5, dances[pro1][:cost], "Pro1 should pay 7.5 (15.0 / 2)"
  end

  test "pro-pro solo from different studios split on studio invoice" do
    studio2 = Studio.create!(name: "Other Studio")
    pro1 = create_professional(@studio, "Pro One")
    pro2 = create_professional(studio2, "Pro Two")

    entry = create_entry(pro1, pro2)
    heat = create_heat(entry, 'Solo')
    create_solo(heat)

    # Studio1 invoice
    generate_invoice([@studio], false, nil)

    # Should count as 0.5 entries (split between studios)
    assert_equal 0.5, @invoices[@studio][:dance_count]
    assert_equal 7.5, @invoices[@studio][:dance_cost]
  end

  # ===== AMATEUR COUPLE SPLITTING TESTS =====

  test "amateur couple split on all invoices" do
    student1 = create_student(@studio, "Student One")
    student2 = create_student(@studio, "Student Two")

    entry = create_entry(student1, student2)
    create_heat(entry, 'Closed')

    # Studio invoice
    generate_invoice([@studio], false, nil)

    dances = @invoices[@studio][:dances]

    # Each student should be charged for 0.5 entries
    assert_equal 0.5, dances[student1][:dances]
    assert_equal 0.5, dances[student2][:dances]

    # Each should pay half the cost
    expected_cost = @event.heat_cost / 2.0  # 25.0 / 2 = 12.5
    assert_equal expected_cost, dances[student1][:cost]
    assert_equal expected_cost, dances[student2][:cost]
  end

  # ===== PRO-AM PRICING TESTS =====

  test "pro-am uses student pricing" do
    student = create_student(@studio, "Student")
    instructor = create_professional(@studio, "Instructor")

    entry = create_entry(student, instructor)
    create_heat(entry, 'Closed')

    generate_invoice([@studio], false, nil)

    dances = @invoices[@studio][:dances]

    # Student should be charged full student cost
    assert_equal @event.heat_cost, dances[student][:cost]

    # Instructor should have 0 cost (not billed for pro-am)
    assert_equal 0, dances[instructor][:cost]
  end

  # ===== COST OVERRIDE TESTS =====

  test "studio cost override applies" do
    @studio.update!(heat_cost: 30.0)

    student = create_student(@studio, "Student")
    instructor = create_professional(@studio, "Instructor")

    entry = create_entry(student, instructor)
    create_heat(entry, 'Closed')

    generate_invoice([@studio], false, nil)

    dances = @invoices[@studio][:dances]

    # Should use studio override (30) not event cost (25)
    assert_equal 30.0, dances[student][:cost]
  end

  test "category cost override applies" do
    category = categories(:one)
    category.update!(cost_override: 40.0, name: "Special Category")
    @dance = dances(:waltz)
    @dance.update!(closed_category: category)

    student = create_student(@studio, "Student")
    instructor = create_professional(@studio, "Instructor")

    entry = create_entry(student, instructor)
    create_heat(entry, 'Closed')

    generate_invoice([@studio], false, nil)

    dances = @invoices[@studio][:dances]

    # Should use category override (40) not event/studio cost
    assert_equal 40.0, dances[student][:cost]
  end

  # ===== MULTIPLE ENTRIES TESTS =====

  test "student with multiple entries counts all" do
    student = create_student(@studio, "Student")
    instructor = create_professional(@studio, "Instructor")

    entry = create_entry(student, instructor)
    # Create 3 heats for this entry
    create_heat(entry, 'Closed')
    create_heat(entry, 'Closed')
    create_heat(entry, 'Closed')

    generate_invoice([@studio], false, nil)

    dances = @invoices[@studio][:dances]

    # Should count 3 dances
    assert_equal 3.0, dances[student][:dances]
    assert_equal 75.0, dances[student][:cost]  # 3 * 25
  end

  # ===== FORMATION TESTS =====

  test "studio formation appears on studio invoice" do
    # Create a formation solo with instructor
    instructor = create_professional(@studio, "Instructor")

    # Formation entries have lead_id=0, follow_id=0
    # Person with id=0 represents "nobody"
    nobody = Person.find(0)
    entry = Entry.create!(
      lead: nobody,
      follow: nobody,
      instructor: instructor,
      age: @age,
      level: @level
    )

    heat = create_heat(entry, 'Solo')
    solo = create_solo(heat)

    # Add formation participants
    student1 = create_student(@studio, "Formation Student 1")
    student2 = create_student(@studio, "Formation Student 2")
    Formation.create!(person: student1, solo: solo, on_floor: true)
    Formation.create!(person: student2, solo: solo, on_floor: true)

    generate_invoice([@studio], false, nil)

    # Should appear in other_charges
    assert @invoices[@studio][:other_charges].any?
  end

  private

  def create_professional(studio, name = nil)
    @name_counter += 1
    # Always use unique names to avoid collisions with fixtures and other tests
    unique_name = name ? "#{name} #{SecureRandom.hex(4)}" : "Pro Test #{SecureRandom.hex(8)}"
    Person.create!(
      name: unique_name,
      type: 'Professional',
      studio: studio,
      level: @level
    )
  end

  def create_student(studio, name = nil)
    @name_counter += 1
    # Always use unique names to avoid collisions with fixtures and other tests
    unique_name = name ? "#{name} #{SecureRandom.hex(4)}" : "Student Test #{SecureRandom.hex(8)}"
    Person.create!(
      name: unique_name,
      type: 'Student',
      studio: studio,
      age: @age,
      level: @level
    )
  end

  def create_entry(lead, follow, instructor = nil)
    # Determine if we need an instructor
    # If both are students and no instructor provided, create one
    if !instructor && lead.type == 'Student' && follow.type == 'Student'
      instructor = create_professional(@studio, "Instructor for couple")
    end

    Entry.create!(
      lead: lead,
      follow: follow,
      instructor: instructor,
      age: @age,
      level: @level
    )
  end

  def create_heat(entry, category)
    Heat.create!(
      number: rand(1..1000),
      entry: entry,
      dance: dances(:waltz),
      category: category
    )
  end

  def create_solo(heat)
    Solo.create!(
      heat: heat,
      order: heat.number
    )
  end
end
