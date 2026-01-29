require "test_helper"

# Comprehensive tests for invoice view rendering.
# These tests verify that the invoice partials correctly filter and display
# data based on invoice type (studio, student, instructor).
#
# Tests cover:
# - Student invoice filtering (excludes professionals)
# - Instructor invoice filtering (excludes non-invoice_to people)
# - Studio invoice display (shows all people)
# - Correct total calculations based on filtered people
# - Entry detail display (combo dances, pro solo levels, splitting)

class StudiosInvoiceViewTest < ActionView::TestCase
  setup do
    @event = events(:one)
    Event.current = @event

    # Create test studio with clean data
    @studio = Studio.create!(name: "Test Studio #{SecureRandom.hex(8)}")
    @age = ages(:one)
    @level = levels(:one)

    # Set up event pricing
    @event.update!(
      heat_cost: 25.0,
      solo_cost: 55.0,
      pro_heat_cost: 10.0,
      pro_solo_cost: 15.0,
      pro_heats: true
    )

    # Set view instance variables that partials expect
    @event = Event.current
    @locale = 'en'
    @couples = {}  # Hash of coupled person IDs
    @registration = 0
    @track_ages = false
    @offered = {freestyles: true, solos: true, multis: false}

    # Set cost hashes (from generate_invoice)
    @cost = {
      'Closed' => @event.heat_cost,
      'Open' => @event.heat_cost,
      'Solo' => @event.solo_cost,
      'Multi' => @event.multi_cost || 0
    }
    @pcost = {
      'Closed' => @event.pro_heat_cost,
      'Open' => @event.pro_heat_cost,
      'Solo' => @event.pro_solo_cost,
      'Multi' => @event.pro_multi_cost || 0
    }
    @heat_cost = @event.heat_cost
    @solo_cost = @event.solo_cost
    @multi_cost = @event.multi_cost || 0
  end

  # ===== STUDENT INVOICE VIEW TESTS =====

  test "student invoice view filters out professionals" do
    student = create_student(@studio, "Student")
    instructor = create_professional(@studio, "Instructor")

    # Create invoice data structure (matching what generate_invoice returns)
    invoice = {
      dances: {
        student => {dances: 5, cost: 125.0, purchases: 0},
        instructor => {dances: 0, cost: 0, purchases: 0}
      },
      purchases: 0,
      other_charges: {},
      entries: {}  # No detailed entries needed for this test
    }

    # Set instance variables as the controller would
    @student = true
    @instructor = student

    # Render the invoice partial
    rendered = render partial: 'studios/invoice', locals: {studio: @studio, invoice: invoice}

    # Should show student name but not instructor name
    assert_match student.name, rendered
    assert_no_match instructor.name, rendered
  end

  test "student invoice view shows correct totals for filtered people" do
    student1 = create_student(@studio, "Student One")
    student2 = create_student(@studio, "Student Two")
    instructor = create_professional(@studio, "Instructor")

    invoice = {
      dances: {
        student1 => {dances: 3, cost: 75.0, purchases: 0},
        student2 => {dances: 2, cost: 50.0, purchases: 0},
        instructor => {dances: 0, cost: 0, purchases: 0}
      },
      purchases: 0,
      other_charges: {},
      entries: {}
    }

    @student = true
    @instructor = student1

    rendered = render partial: 'studios/invoice', locals: {studio: @studio, invoice: invoice}

    # Should show student1 name
    assert_match student1.name, rendered
    # Should show student1's dance count in the summary table
    assert_match ">3<", rendered  # 3 dances in a table cell
    # Should show student1's total cost
    assert_match "75.00", rendered
  end

  # ===== INSTRUCTOR INVOICE VIEW TESTS =====

  test "instructor invoice view filters out people not billed to instructor" do
    instructor = create_professional(@studio, "Instructor")
    other_pro = create_professional(@studio, "Other Pro")

    invoice = {
      dances: {
        instructor => {dances: 2.5, cost: 37.5, purchases: 0},
        other_pro => {dances: 1.5, cost: 22.5, purchases: 0}
      },
      purchases: 0,
      other_charges: {},
      entries: {}
    }

    @student = false
    @instructor = instructor

    rendered = render partial: 'studios/invoice', locals: {studio: @studio, invoice: invoice}

    # Should show instructor but not other_pro
    assert_match instructor.name, rendered
    assert_no_match other_pro.name, rendered
  end

  test "instructor invoice view includes people with invoice_to_id" do
    instructor = create_professional(@studio, "Instructor")
    dependent = create_professional(@studio, "Dependent")
    dependent.update!(invoice_to_id: instructor.id)

    invoice = {
      dances: {
        instructor => {dances: 2, cost: 30.0, purchases: 0},
        dependent => {dances: 1, cost: 15.0, purchases: 0}
      },
      purchases: 0,
      other_charges: {},
      entries: {}
    }

    @student = false
    @instructor = instructor

    rendered = render partial: 'studios/invoice', locals: {studio: @studio, invoice: invoice}

    # Should show both instructor and dependent
    assert_match instructor.name, rendered
    assert_match dependent.name, rendered
    # Should total both
    assert_match "45", rendered  # 30 + 15
  end

  # ===== STUDIO INVOICE VIEW TESTS =====

  test "studio invoice view shows all people" do
    student = create_student(@studio, "Student")
    instructor = create_professional(@studio, "Instructor")

    invoice = {
      dances: {
        student => {dances: 5, cost: 125.0, purchases: 0},
        instructor => {dances: 2, cost: 30.0, purchases: 0}
      },
      purchases: 0,
      other_charges: {},
      entries: {}
    }

    @student = false
    @instructor = nil

    rendered = render partial: 'studios/invoice', locals: {studio: @studio, invoice: invoice}

    # Should show both student and instructor
    assert_match student.name, rendered
    assert_match instructor.name, rendered
    # Should total both
    assert_match "155", rendered  # 125 + 30
  end

  # ===== ENTRY DETAIL VIEW TESTS =====

  test "entry partial shows full count for student-student same-studio on studio invoice" do
    student1 = create_student(@studio, "Student One")
    student2 = create_student(@studio, "Student Two")

    # Create a dance and category with unique order values
    order = (Category.maximum(:order) || 0) + rand(1000) + 1
    category = Category.create!(name: "Test Cat #{SecureRandom.hex(4)}", order: order)
    dance = Dance.create!(name: "Test Dance #{SecureRandom.hex(4)}", closed_category: category, order: order)

    # Create entry with heats (category: 'Closed' to match @cost lookup)
    entry = create_entry(student1, student2)
    3.times { Heat.create!(entry: entry, dance: dance, number: Heat.maximum(:number).to_i + 1, category: 'Closed') }

    # Set up instance variables for the partial
    @student = false
    @instructor = nil

    # Render the entry partial as studio invoice
    rendered = render partial: 'studios/entry', locals: {
      names: [student1, student2],
      entries: [entry],
      studio: @studio.name,
      invoice: :studio,
      partner: nil
    }

    # Should show full count (3), not split (1.5)
    assert_match ">3<", rendered, "Studio invoice should show full heat count for same-studio student couple"
    assert_no_match "1.5", rendered, "Studio invoice should NOT split count for same-studio student couple"

    # Verify the full cost (3 heats * $25 = $75)
    assert_match "75", rendered
  end

  test "entry partial splits count for student-student on student invoice without partner" do
    student1 = create_student(@studio, "Student One")
    student2 = create_student(@studio, "Student Two")

    order = (Category.maximum(:order) || 0) + rand(1000) + 1
    category = Category.create!(name: "Test Cat #{SecureRandom.hex(4)}", order: order)
    dance = Dance.create!(name: "Test Dance #{SecureRandom.hex(4)}", closed_category: category, order: order)

    entry = create_entry(student1, student2)
    2.times { Heat.create!(entry: entry, dance: dance, number: Heat.maximum(:number).to_i + 1, category: 'Closed') }

    @student = true
    @instructor = nil

    # Render as student invoice (no partner relationship)
    rendered = render partial: 'studios/entry', locals: {
      names: [student1, student2],
      entries: [entry],
      studio: @studio.name,
      invoice: :student,
      partner: nil
    }

    # Should show split count (1), not full (2)
    assert_match ">1<", rendered, "Student invoice should show split count"
    # Cost should be split too (1 heat * $25 = $25)
    assert_match "25.00", rendered
  end

  test "entry partial shows full count for student-student on student invoice with partner" do
    student1 = create_student(@studio, "Student One")
    student2 = create_student(@studio, "Student Two")

    order = (Category.maximum(:order) || 0) + rand(1000) + 1
    category = Category.create!(name: "Test Cat #{SecureRandom.hex(4)}", order: order)
    dance = Dance.create!(name: "Test Dance #{SecureRandom.hex(4)}", closed_category: category, order: order)

    entry = create_entry(student1, student2)
    4.times { Heat.create!(entry: entry, dance: dance, number: Heat.maximum(:number).to_i + 1, category: 'Closed') }

    @student = true
    @instructor = nil

    # Render as student invoice with partner (couple relationship)
    rendered = render partial: 'studios/entry', locals: {
      names: [student1, student2],
      entries: [entry],
      studio: @studio.name,
      invoice: :student,
      partner: student2  # student1 viewing with student2 as partner
    }

    # Should show full count (4) because they're a couple
    assert_match ">4<", rendered, "Student invoice with partner should show full count"
    # Full cost (4 * $25 = $100)
    assert_match "100", rendered
  end

  test "entry partial uses pro_multi_cost for pro-pro multi-dance entries" do
    pro1 = create_professional(@studio, "Pro One")
    pro2 = create_professional(@studio, "Pro Two")

    # Set up pricing: multi_cost=$75, pro_multi_cost=$0
    @cost['Multi'] = 75.0
    @pcost['Multi'] = 0.0

    order = (Category.maximum(:order) || 0) + rand(1000) + 1
    category = Category.create!(name: "Pro Multi Cat #{SecureRandom.hex(4)}", order: order)
    dance = Dance.create!(
      name: "Pro Multi Dance #{SecureRandom.hex(4)}",
      pro_multi_category: category,
      order: order,
      heat_length: 3  # marks it as a multi-dance
    )

    entry = Entry.create!(lead: pro1, follow: pro2, age: @age, level: @level)
    Heat.create!(entry: entry, dance: dance, number: Heat.maximum(:number).to_i + 1, category: 'Multi')

    @student = false
    @instructor = nil

    rendered = render partial: 'studios/entry', locals: {
      names: [pro1, pro2],
      entries: [entry],
      studio: @studio.name,
      invoice: :studio,
      partner: nil
    }

    # Should use @pcost['Multi'] = $0, not @cost['Multi'] = $75
    assert_match ">1<", rendered, "Should show 1 multi-dance entry"
    # The cost should be $0 (pro rate), not $75 (regular rate)
    # Check that 75.00 doesn't appear as a price (avoid matching random hex in names)
    assert_no_match ">75.00<", rendered, "Pro-pro multi should NOT use regular multi_cost ($75)"
    # Line item cost should be 0.00
    assert_match ">0.00<", rendered, "Pro-pro multi cost should be $0"
  end

  private

  def create_professional(studio, name = nil)
    unique_name = name ? "#{name} #{SecureRandom.hex(4)}" : "Pro Test #{SecureRandom.hex(8)}"
    Person.create!(
      name: unique_name,
      type: 'Professional',
      studio: studio,
      level: @level
    )
  end

  def create_student(studio, name = nil)
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
end
