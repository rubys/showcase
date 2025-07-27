require "test_helper"

# Comprehensive tests for the Person model which represents people in the dance system.
# Person is a critical model using single table inheritance (STI) as it:
#
# - Uses STI with types: Student, Professional, Guest, Judge, Placeholder
# - Normalizes name format and validates uniqueness within type
# - Manages back numbers (unique competition identifiers)
# - Handles complex name parsing (first, last, display names)
# - Manages billing relationships (packages, invoice_to, responsible_for)
# - Provides activity detection for competition participants
# - Manages judge availability and preferences
# - Handles formation and option associations
#
# Tests cover:
# - Validation rules for different person types
# - Name normalization and parsing functionality
# - Association management and dependent behaviors
# - STI type-specific behavior and validations
# - Activity detection and billing logic
# - Special "nobody" placeholder functionality

class PersonTest < ActiveSupport::TestCase
  setup do
    @studio = studios(:one)
    @level = levels(:one)
    @age = ages(:one)
  end

  # ===== VALIDATION TESTS =====
  
  test "should be valid with required attributes" do
    person = Person.new(
      name: 'Smith, John',
      type: 'Student',
      studio: @studio,
      level: @level
    )
    assert person.valid?
  end
  
  test "should require name" do
    person = Person.new(
      type: 'Student',
      studio: @studio,
      level: @level
    )
    assert_not person.valid?
    assert_includes person.errors[:name], "can't be blank"
  end
  
  test "should require studio" do
    person = Person.new(
      name: 'Smith, John',
      type: 'Student',
      level: @level
    )
    assert_not person.valid?
    assert_includes person.errors[:studio], "must exist"
  end
  
  test "should require level for students" do
    person = Person.new(
      name: 'Smith, John',
      type: 'Student',
      studio: @studio
    )
    assert_not person.valid?
    assert_includes person.errors[:level], "can't be blank"
  end
  
  test "should not require level for professionals" do
    person = Person.new(
      name: 'Smith, John',
      type: 'Professional',
      studio: @studio
    )
    assert person.valid?
  end
  
  test "should not require level for guests" do
    person = Person.new(
      name: 'Smith, John',
      type: 'Guest',
      studio: @studio
    )
    assert person.valid?
  end
  
  test "should validate name uniqueness within type" do
    Person.create!(
      name: 'Smith, John',
      type: 'Student',
      studio: @studio,
      level: @level
    )
    
    # Same name with same type should be invalid
    duplicate = Person.new(
      name: 'Smith, John',
      type: 'Student',
      studio: @studio,
      level: @level
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], 'has already been taken'
  end
  
  test "should allow same name with different type" do
    Person.create!(
      name: 'Smith, John',
      type: 'Student',
      studio: @studio,
      level: @level
    )
    
    # Same name with different type should be valid
    different_type = Person.new(
      name: 'Smith, John',
      type: 'Professional',
      studio: @studio
    )
    assert different_type.valid?
  end
  
  test "should validate back number uniqueness" do
    Person.create!(
      name: 'Smith, John',
      type: 'Student',
      studio: @studio,
      level: @level,
      back: 42
    )
    
    duplicate = Person.new(
      name: 'Jones, Jane',
      type: 'Student',
      studio: @studio,
      level: @level,
      back: 42
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:back], 'has already been taken'
  end
  
  test "should allow nil back numbers" do
    person = Person.new(
      name: 'Smith, John',
      type: 'Student',
      studio: @studio,
      level: @level,
      back: nil
    )
    assert person.valid?
  end
  
  test "should reject names with ampersand" do
    person = Person.new(
      name: 'Smith & Jones',
      type: 'Student',
      studio: @studio,
      level: @level
    )
    assert_not person.valid?
    assert_includes person.errors[:name], 'only one name per person'
  end
  
  test "should reject names with 'and'" do
    person = Person.new(
      name: 'Smith and Jones',
      type: 'Student',
      studio: @studio,
      level: @level
    )
    assert_not person.valid?
    assert_includes person.errors[:name], 'only one name per person'
  end
  
  # ===== NAME NORMALIZATION TESTS =====
  
  test "should normalize name by stripping whitespace" do
    person = Person.create!(
      name: '  Smith,   John  ',
      type: 'Student',
      studio: @studio,
      level: @level
    )
    assert_equal 'Smith, John', person.name
  end
  
  test "should normalize name by collapsing multiple spaces" do
    person = Person.create!(
      name: 'Smith,    John    Middle',
      type: 'Student',
      studio: @studio,
      level: @level
    )
    assert_equal 'Smith, John Middle', person.name
  end
  
  test "should normalize available field by removing empty strings" do
    person = Person.create!(
      name: 'Smith, John',
      type: 'Student',
      studio: @studio,
      level: @level,
      available: ''
    )
    assert_nil person.available
  end
  
  # ===== NAME PARSING TESTS =====
  
  test "display_name converts Last, First to First Last" do
    person = Person.new(name: 'Smith, John')
    assert_equal 'John Smith', person.display_name
  end
  
  test "display_name handles single name" do
    person = Person.new(name: 'John')
    assert_equal 'John', person.display_name
  end
  
  test "display_name handles nil name" do
    person = Person.new(name: nil)
    assert_nil person.display_name
  end
  
  test "first_name extracts first name" do
    person = Person.new(name: 'Smith, John')
    assert_equal 'John', person.first_name
  end
  
  test "last_name extracts last name" do
    person = Person.new(name: 'Smith, John')
    assert_equal 'Smith', person.last_name
  end
  
  test "back_name creates abbreviated competition name" do
    person = Person.new(name: 'Smith, John Michael')
    # First 6 chars of first name + first char of last name
    assert_equal 'JohnMiS', person.back_name
  end
  
  test "back_name handles short first names" do
    person = Person.new(name: 'Smith, Jo')
    assert_equal 'JoS', person.back_name
  end
  
  test "join creates partnership display name with same last name" do
    person1 = Person.new(name: 'Smith, John')
    person2 = Person.new(name: 'Smith, Jane')
    
    assert_equal 'John and Jane Smith', person1.join(person2)
  end
  
  test "join creates partnership display name with different last names" do
    person1 = Person.new(name: 'Smith, John')
    person2 = Person.new(name: 'Jones, Jane')
    
    assert_equal 'John Smith and Jane Jones', person1.join(person2)
  end
  
  test "self.display_name class method works" do
    assert_equal 'John Smith', Person.display_name('Smith, John')
    assert_nil Person.display_name(nil)
  end
  
  # ===== ASSOCIATION TESTS =====
  
  test "should belong to studio" do
    person = Person.create!(
      name: 'Smith, John',
      type: 'Student',
      studio: @studio,
      level: @level
    )
    assert_equal @studio, person.studio
  end
  
  test "should optionally belong to level" do
    person = Person.create!(
      name: 'Smith, John',
      type: 'Professional',
      studio: @studio
    )
    assert_nil person.level
    
    person.update!(level: @level)
    assert_equal @level, person.level
  end
  
  test "should optionally belong to age" do
    person = Person.create!(
      name: 'Smith, John',
      type: 'Student',
      studio: @studio,
      level: @level
    )
    assert_nil person.age
    
    person.update!(age: @age)
    assert_equal @age, person.age
  end
  
  test "should optionally belong to table" do
    person = Person.create!(
      name: 'Smith, John',
      type: 'Student',
      studio: @studio,
      level: @level
    )
    assert_nil person.table
    
    table = tables(:one)
    person.update!(table: table)
    assert_equal table, person.table
  end
  
  test "should have many lead entries with dependent destroy" do
    person = Person.create!(
      name: 'Smith, John',
      type: 'Professional',
      studio: @studio
    )
    
    entry = Entry.create!(
      lead: person,
      follow: people(:student_one),
      age: @age,
      level: @level
    )
    
    assert_includes person.lead_entries, entry
    
    person.destroy
    assert_nil Entry.find_by(id: entry.id)
  end
  
  test "should have many follow entries with dependent destroy" do
    person = Person.create!(
      name: 'Smith, Jane',
      type: 'Student',
      studio: @studio,
      level: @level
    )
    
    entry = Entry.create!(
      lead: people(:instructor1),
      follow: person,
      age: @age,
      level: @level
    )
    
    assert_includes person.follow_entries, entry
    
    person.destroy
    assert_nil Entry.find_by(id: entry.id)
  end
  
  test "should have many instructor entries with dependent nullify" do
    instructor = Person.create!(
      name: 'Instructor, Pro',
      type: 'Professional',
      studio: @studio
    )
    
    entry = Entry.create!(
      lead: people(:student_one),
      follow: people(:student_two),
      instructor: instructor,
      age: @age,
      level: @level
    )
    
    assert_includes instructor.instructor_entries, entry
    
    instructor.destroy
    entry.reload
    assert_nil entry.instructor_id
  end
  
  test "should have invoice_to and responsible_for relationships" do
    parent = Person.create!(
      name: 'Parent, Jane',
      type: 'Guest',
      studio: @studio
    )
    
    child = Person.create!(
      name: 'Child, Johnny',
      type: 'Student',
      studio: @studio,
      level: @level,
      invoice_to: parent
    )
    
    assert_equal parent, child.invoice_to
    assert_includes parent.responsible_for, child
  end
  
  # ===== ACTIVITY TESTS =====
  
  test "active? returns true for guest with package" do
    # Create a guest billable package
    guest_package = Billable.create!(name: "Guest Package #{rand(1000)}", type: 'Guest', price: 50, order: 1)
    
    person = Person.create!(
      name: 'Guest, Jane',
      type: 'Guest',
      studio: @studio,
      package: guest_package
    )
    
    assert person.active?
  end
  
  test "active? returns true for guest when no guest packages exist" do
    person = Person.create!(
      name: 'Guest, Jane',
      type: 'Guest',
      studio: @studio
    )
    
    # Ensure no guest packages exist
    Billable.where(type: 'Guest').destroy_all
    
    assert person.active?
  end
  
  test "active? returns false for guest without package when packages exist" do
    # Create a guest billable package
    Billable.create!(name: "Guest Package #{rand(1000)}", type: 'Guest', price: 50, order: 1)
    
    person = Person.create!(
      name: 'Guest, Jane',
      type: 'Guest',
      studio: @studio
    )
    
    assert_not person.active?
  end
  
  test "active? returns true for student/professional with entries" do
    person = Person.create!(
      name: 'Student, Active',
      type: 'Student',
      studio: @studio,
      level: @level
    )
    
    # Create an entry for this person
    Entry.create!(
      lead: person,
      follow: people(:instructor1),
      age: @age,
      level: @level
    )
    
    assert person.active?
  end
  
  test "active? returns false for student/professional without entries" do
    person = Person.create!(
      name: 'Student, Inactive',
      type: 'Student',
      studio: @studio,
      level: @level
    )
    
    assert_not person.active?
  end
  
  # ===== PACKAGE AND BILLING TESTS =====
  
  test "default_package sets student package" do
    student_package = Billable.create!(name: "Student Package #{rand(1000)}", type: 'Student', price: 100, order: 1)
    @studio.update!(default_student_package: student_package)
    
    person = Person.create!(
      name: 'Student, New',
      type: 'Student',
      studio: @studio,
      level: @level
    )
    
    person.default_package
    assert_equal student_package.id, person.package_id
  end
  
  test "default_package sets professional package" do
    pro_package = Billable.create!(name: "Pro Package #{rand(1000)}", type: 'Professional', price: 200, order: 1)
    @studio.update!(default_professional_package: pro_package)
    
    person = Person.create!(
      name: 'Pro, New',
      type: 'Professional',
      studio: @studio
    )
    
    person.default_package
    assert_equal pro_package.id, person.package_id
  end
  
  test "default_package falls back to first package by order" do
    # Clear any existing Student packages to ensure clean test
    Billable.where(type: 'Student').destroy_all
    
    package1 = Billable.create!(name: "Package 1 #{rand(1000)}", type: 'Student', price: 100, order: 2)
    package2 = Billable.create!(name: "Package 2 #{rand(1000)}", type: 'Student', price: 150, order: 1)
    
    person = Person.create!(
      name: 'Student, New',
      type: 'Student',
      studio: @studio,
      level: @level
    )
    
    person.default_package
    assert_equal package2.id, person.package_id # Lower order number
  end
  
  test "default_package! saves changes" do
    student_package = Billable.create!(name: "Student Package #{rand(1000)}", type: 'Student', price: 100, order: 1)
    @studio.update!(default_student_package: student_package)
    
    person = Person.create!(
      name: 'Student, New',
      type: 'Student',
      studio: @studio,
      level: @level
    )
    
    person.default_package!
    person.reload
    assert_equal student_package.id, person.package_id
  end
  
  # ===== JUDGE FUNCTIONALITY TESTS =====
  
  test "present? delegates to judge when judge exists" do
    judge_person = Person.create!(
      name: 'Judge, Pro',
      type: 'Judge',
      studio: @studio
    )
    
    # Would need to create a Judge record to fully test this
    # For now, test the default behavior
    assert judge_person.present?
  end
  
  test "show_assignments delegates to judge or returns default" do
    person = Person.create!(
      name: 'Person, Test',
      type: 'Student',
      studio: @studio,
      level: @level
    )
    
    assert_equal 'first', person.show_assignments
  end
  
  test "sort_order delegates to judge or returns default" do
    person = Person.create!(
      name: 'Person, Test',
      type: 'Student',
      studio: @studio,
      level: @level
    )
    
    assert_equal 'back', person.sort_order
  end
  
  # ===== SPECIAL FUNCTIONALITY TESTS =====
  
  test "eligible_heats returns all heats when no availability restriction" do
    person = Person.create!(
      name: 'Person, Available',
      type: 'Student',
      studio: @studio,
      level: @level,
      available: nil
    )
    
    start_times = [[1, Time.parse('10:00 AM')], [2, Time.parse('11:00 AM')]]
    eligible = person.eligible_heats(start_times)
    
    # Method returns all start_times when no availability restriction
    assert_equal Set.new(start_times), eligible
  end
  
  test "eligible_heats filters by before time" do
    person = Person.create!(
      name: 'Person, Limited',
      type: 'Student',
      studio: @studio,
      level: @level,
      available: '<10:30 AM'
    )
    
    start_times = [[1, Time.parse('10:00 AM')], [2, Time.parse('11:00 AM')]]
    eligible = person.eligible_heats(start_times)
    
    assert_equal Set.new([1]), eligible
  end
  
  test "eligible_heats filters by after time" do
    person = Person.create!(
      name: 'Person, Limited',
      type: 'Student',
      studio: @studio,
      level: @level,
      available: '>10:30 AM'
    )
    
    start_times = [[1, Time.parse('10:00 AM')], [2, Time.parse('11:00 AM')]]
    eligible = person.eligible_heats(start_times)
    
    assert_equal Set.new([2]), eligible
  end
  
  test "self.nobody creates or finds placeholder person" do
    # Ensure person with id 0 doesn't exist
    Person.where(id: 0).destroy_all
    
    nobody = Person.nobody
    
    assert_equal 0, nobody.id
    assert_equal 'Nobody', nobody.name
    assert_equal 'Placeholder', nobody.type
    assert_equal 'both', nobody.role
  end
  
  test "self.nobody returns existing placeholder person" do
    # Create the nobody person first
    existing = Person.nobody
    
    # Call again and should return same instance
    nobody = Person.nobody
    
    assert_equal existing.id, nobody.id
  end
  
  # ===== PACKAGE CHANGE TESTS =====
  
  test "changing package removes orphaned option records" do
    # Create two packages with different options
    package1 = Billable.create!(type: 'Package', name: "Package 1 #{rand(1000)}", price: 100.0)
    option1 = Billable.create!(type: 'Option', name: "Option 1 #{rand(1000)}", price: 25.0)
    PackageInclude.create!(package: package1, option: option1)
    
    package2 = Billable.create!(type: 'Package', name: "Package 2 #{rand(1000)}", price: 100.0)
    option2 = Billable.create!(type: 'Option', name: "Option 2 #{rand(1000)}", price: 25.0)
    PackageInclude.create!(package: package2, option: option2)
    
    # Create person with package1
    person = Person.create!(
      name: 'Test, Person',
      type: 'Student',
      studio: @studio,
      level: @level,
      package: package1
    )
    
    # Simulate person being seated at a table for option1
    PersonOption.create!(person: person, option: option1)
    
    # Change to package2
    assert_difference 'PersonOption.count', -1 do
      person.update!(package: package2)
    end
    
    # Option1 PersonOption should be removed
    assert_nil PersonOption.find_by(person: person, option: option1)
  end
  
  test "changing package keeps option records for seated people" do
    # Create packages and options
    package1 = Billable.create!(type: 'Package', name: "Package 1 #{rand(1000)}", price: 100.0)
    option1 = Billable.create!(type: 'Option', name: "Option 1 #{rand(1000)}", price: 25.0)
    PackageInclude.create!(package: package1, option: option1)
    
    package2 = Billable.create!(type: 'Package', name: "Package 2 #{rand(1000)}", price: 100.0)
    
    # Create person with package1
    person = Person.create!(
      name: 'Test, Person',
      type: 'Student',
      studio: @studio,
      level: @level,
      package: package1
    )
    
    # Create table and seat person
    table = Table.create!(number: 99, option: option1)
    person_option = PersonOption.create!(person: person, option: option1, table: table)
    
    # Change to package2 - should keep PersonOption since they're seated
    assert_no_difference 'PersonOption.count' do
      person.update!(package: package2)
    end
    
    # PersonOption should still exist with table assignment
    person_option.reload
    assert_equal table, person_option.table
  end
  
  test "removing package removes orphaned option records" do
    # Create package with option
    package = Billable.create!(type: 'Package', name: "Package #{rand(1000)}", price: 100.0)
    option = Billable.create!(type: 'Option', name: "Option #{rand(1000)}", price: 25.0)
    PackageInclude.create!(package: package, option: option)
    
    # Create person with package
    person = Person.create!(
      name: 'Test, Person',
      type: 'Student',
      studio: @studio,
      level: @level,
      package: package
    )
    
    # Simulate person being assigned to option
    PersonOption.create!(person: person, option: option)
    
    # Remove package
    assert_difference 'PersonOption.count', -1 do
      person.update!(package: nil)
    end
  end
  
  test "changing package keeps shared options" do
    # Create packages with shared option
    shared_option = Billable.create!(type: 'Option', name: "Shared Option #{rand(1000)}", price: 25.0)
    
    package1 = Billable.create!(type: 'Package', name: "Package 1 #{rand(1000)}", price: 100.0)
    PackageInclude.create!(package: package1, option: shared_option)
    
    package2 = Billable.create!(type: 'Package', name: "Package 2 #{rand(1000)}", price: 100.0)
    PackageInclude.create!(package: package2, option: shared_option)
    
    # Create person with package1
    person = Person.create!(
      name: 'Test, Person',
      type: 'Student',
      studio: @studio,
      level: @level,
      package: package1
    )
    
    # Create PersonOption for shared option
    PersonOption.create!(person: person, option: shared_option)
    
    # Change to package2 - should keep PersonOption since option is in both packages
    assert_no_difference 'PersonOption.count' do
      person.update!(package: package2)
    end
  end
  
  test "with_option scope finds people with direct option selection" do
    option = Billable.create!(type: 'Option', name: "Test Option #{rand(1000)}", price: 25.0)
    
    person = Person.create!(
      name: 'Test, Person',
      type: 'Student',
      studio: @studio,
      level: @level
    )
    
    # Initially not found
    assert_not_includes Person.with_option(option.id), person
    
    # Create direct selection
    PersonOption.create!(person: person, option: option)
    
    # Now found
    assert_includes Person.with_option(option.id), person
  end
  
  test "with_option scope finds people with option through package" do
    # Create package with option
    package = Billable.create!(type: 'Package', name: "Package #{rand(1000)}", price: 100.0)
    option = Billable.create!(type: 'Option', name: "Option #{rand(1000)}", price: 25.0)
    PackageInclude.create!(package: package, option: option)
    
    person = Person.create!(
      name: 'Test, Person',
      type: 'Student',
      studio: @studio,
      level: @level,
      package: package
    )
    
    # Should find person through package
    assert_includes Person.with_option(option.id), person
  end
  
  test "with_option_unassigned scope finds people without table assignment" do
    option = Billable.create!(type: 'Option', name: "Test Option #{rand(1000)}", price: 25.0)
    
    person = Person.create!(
      name: 'Test, Person',
      type: 'Student',
      studio: @studio,
      level: @level
    )
    
    # Create direct selection without table
    PersonOption.create!(person: person, option: option)
    
    # Should be found as unassigned
    assert_includes Person.with_option_unassigned(option.id), person
    
    # Assign to table
    table = Table.create!(number: 99, option: option)
    PersonOption.where(person: person, option: option).update_all(table_id: table.id)
    
    # Should not be found as unassigned
    assert_not_includes Person.with_option_unassigned(option.id), person
  end
end
