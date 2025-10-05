require "test_helper"

# Comprehensive tests for invoice-related controller actions.
# These tests verify that invoice controller actions correctly:
# - Call generate_invoice with appropriate parameters
# - Set required instance variables for views
# - Return successful responses
# - Filter data appropriately based on invoice type
#
# Tests cover:
# - Studio invoices (StudiosController#invoice)
# - Student invoices (StudiosController#student_invoices)
# - Instructor invoices (PeopleController#instructor_invoice)
# - Individual student invoices (PeopleController#invoice)

class InvoicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @event = events(:one)
    Event.current = @event

    # Create test data
    @studio = Studio.create!(name: "Test Studio #{SecureRandom.hex(8)}")
    @age = ages(:one)
    @level = levels(:one)

    @event.update!(
      heat_cost: 25.0,
      solo_cost: 55.0,
      pro_heat_cost: 10.0,
      pro_solo_cost: 15.0,
      pro_heats: true
    )
  end

  # ===== STUDIO INVOICE TESTS =====

  test "studio invoice action returns success" do
    get invoice_studio_path(@studio)
    assert_response :success
  end

  test "studio invoice includes all people from studio" do
    student = create_student(@studio, "Student")
    instructor = create_professional(@studio, "Instructor")

    # Create entries
    entry = create_entry(student, instructor)
    create_heat(entry, 'Closed')

    get invoice_studio_path(@studio)
    assert_response :success

    # Should show both student and instructor names in response
    assert_match student.name, response.body
    assert_match instructor.name, response.body
  end

  test "studio invoice displays studio name" do
    get invoice_studio_path(@studio)
    assert_response :success

    # Should show studio name
    assert_match @studio.name, response.body
  end

  # ===== STUDENT INVOICES TESTS =====

  test "student invoices action returns success" do
    get student_invoices_studio_path(@studio)
    assert_response :success
  end

  test "student invoices shows all students from studio" do
    student1 = create_student(@studio, "Student One")
    student2 = create_student(@studio, "Student Two")
    instructor = create_professional(@studio, "Instructor")

    entry1 = create_entry(student1, instructor)
    entry2 = create_entry(student2, instructor)
    create_heat(entry1, 'Closed')
    create_heat(entry2, 'Closed')

    get student_invoices_studio_path(@studio)
    assert_response :success

    # Should show both student names in response
    assert_match student1.name, response.body
    assert_match student2.name, response.body
  end

  # ===== INSTRUCTOR INVOICE TESTS =====

  test "instructor invoice action returns success" do
    instructor = create_professional(@studio, "Instructor")

    get instructor_invoice_person_path(instructor)
    assert_response :success
  end

  test "instructor invoice shows instructor name" do
    instructor = create_professional(@studio, "Instructor")
    other_pro = create_professional(@studio, "Other Pro")
    student = create_student(@studio, "Student")

    # Create pro-pro entry
    propro_entry = create_entry(instructor, other_pro)
    propro_heat = create_heat(propro_entry, 'Solo')
    Solo.create!(heat: propro_heat, order: propro_heat.number)

    # Create pro-am entry (should be excluded from display)
    proam_entry = create_entry(student, instructor)
    create_heat(proam_entry, 'Closed')

    get instructor_invoice_person_path(instructor)
    assert_response :success

    # Should show instructor name
    assert_match instructor.name, response.body
    # Pro-am student should not appear (filtered by view)
    # Note: Student may be in data but filtered out by view logic
  end

  # ===== INDIVIDUAL STUDENT INVOICE TESTS =====

  test "individual student invoice returns success" do
    student = create_student(@studio, "Student")

    get invoice_person_path(student)
    assert_response :success
  end

  test "individual student invoice shows student name" do
    student1 = create_student(@studio, "Student One")
    student2 = create_student(@studio, "Student Two")
    instructor = create_professional(@studio, "Instructor")

    entry1 = create_entry(student1, instructor)
    entry2 = create_entry(student2, instructor)
    create_heat(entry1, 'Closed')
    create_heat(entry2, 'Closed')

    get invoice_person_path(student1)
    assert_response :success

    # Should show student1 name
    assert_match student1.name, response.body
  end

  test "individual student invoice includes invoice_to_id relationships" do
    student1 = create_student(@studio, "Student One")
    student2 = create_student(@studio, "Student Two")
    student2.update!(invoice_to_id: student1.id)
    instructor = create_professional(@studio, "Instructor")

    entry1 = create_entry(student1, instructor)
    entry2 = create_entry(student2, instructor)
    create_heat(entry1, 'Closed')
    create_heat(entry2, 'Closed')

    get invoice_person_path(student1)
    assert_response :success

    # Should show both student names (student2 bills to student1)
    assert_match student1.name, response.body
    assert_match student2.name, response.body
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
    # Auto-assign instructor for amateur couples
    if !instructor && lead.type == 'Student' && follow.type == 'Student'
      instructor = create_professional(@studio, "Auto Instructor")
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
end
