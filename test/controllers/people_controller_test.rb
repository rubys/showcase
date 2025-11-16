require "test_helper"

class PeopleControllerTest < ActionDispatch::IntegrationTest
  setup do
    @person = people(:Arthur)
  end

  test "should get index" do
    get people_url
    assert_response :success
  end

  test "should get new" do
    get new_person_url
    assert_response :success
  end

  test "should get heat sheets" do
    get heats_people_url
    assert_response :success
  end

  test "should get individual heat sheet" do
    get heats_person_url(@person)
    assert_response :success
  end

  test "should get students scores" do
    get scores_people_url
    assert_response :success
  end

  test "should get individual scores" do
    get scores_person_url(@person)
    assert_response :success
  end

  test "should create person" do
    assert_difference("Person.count") do
      post people_url, params: { person: { age_id: @person.age_id, back: 301, level_id: @person.level_id, name: 'Fred Astaire', role: @person.role, studio_id: @person.studio_id, type: @person.type, exclude_id: '' } }
    assert_equal flash[:notice], 'Fred Astaire was successfully added.'
    end

    assert_redirected_to person_url(Person.last)
  end

  test "should create judge" do
    assert_difference("Person.count") do
      post people_url, params: { person: { name: 'Joseph Wopner', type: 'Judge', studio_id: 0 } }
    assert_equal flash[:notice], 'Joseph Wopner was successfully added.'
    end

    assert_redirected_to person_url(Person.last)
  end

  test "should show person" do
    get person_url(@person)
    assert_response :success
  end

  test "should get edit" do
    get edit_person_url(@person)
    assert_response :success
  end

  test "should update person" do
    patch person_url(@person), params: { person: { age_id: @person.age_id, back: @person.back, level_id: @person.level_id, name: @person.name, role: @person.role, studio_id: @person.studio_id, type: @person.type, exclude_id: '' } }
    assert_redirected_to person_url(@person)
    assert_equal flash[:notice], 'Arthur Murray was successfully updated.'
  end

  test "should update person with table assignment" do
    table = tables(:one)
    patch person_url(@person), params: { person: { age_id: @person.age_id, back: @person.back, level_id: @person.level_id, name: @person.name, role: @person.role, studio_id: @person.studio_id, type: @person.type, table_id: table.id, exclude_id: '' } }
    assert_redirected_to person_url(@person)
    assert_equal flash[:notice], 'Arthur Murray was successfully updated.'
    @person.reload
    assert_equal table.id, @person.table_id
  end

  test "should show table options for Professional in edit" do
    get edit_person_url(@person)
    assert_response :success
    assert_match /Table \d+ -/, response.body
  end

  test "should show table options for Student in edit" do
    student = people(:Kathryn)
    get edit_person_url(student)
    assert_response :success
    assert_match /Table \d+ -/, response.body
  end

  test "should show table options for Guest in edit" do
    guest = people(:guest)
    get edit_person_url(guest)
    assert_response :success
    assert_match /Table \d+ -/, response.body
  end

  test "should show table options for Judge in edit" do
    judge = people(:Judy)
    get edit_person_url(judge)
    assert_response :success
    assert_match /Table \d+ -/, response.body
  end

  test "should destroy person" do
    assert_difference("Person.count", -1) do
      delete person_url(@person)
    end

    assert_response 303
    assert_redirected_to studio_url(@person.studio)
    assert_equal flash[:notice], 'Arthur Murray was successfully removed.'
  end

  test "should show option table dropdowns for options with tables" do
    # Create an option table
    option = billables(:two) # Lunch option
    option_table = Table.create!(number: 100, option: option, size: 8)
    
    get edit_person_url(@person)
    assert_response :success
    
    # Should show table dropdown for the option
    assert_match /Table 100 -/, response.body
    assert_match /person\[option_tables\]\[#{option.id}\]/, response.body
  end

  test "should save option table assignment when creating person option" do
    option = billables(:two) # Lunch option
    option_table = Table.create!(number: 100, option: option, size: 8)
    
    assert_difference("PersonOption.count", 1) do
      patch person_url(@person), params: { 
        person: { 
          age_id: @person.age_id, 
          back: @person.back, 
          level_id: @person.level_id, 
          name: @person.name, 
          role: @person.role, 
          studio_id: @person.studio_id, 
          type: @person.type, 
          exclude_id: '',
          options: { option.id.to_s => '1' },
          option_tables: { option.id.to_s => option_table.id.to_s }
        } 
      }
    end
    
    assert_redirected_to person_url(@person)
    person_option = PersonOption.last
    assert_equal @person.id, person_option.person_id
    assert_equal option.id, person_option.option_id
    assert_equal option_table.id, person_option.table_id
  end

  test "should update option table assignment for existing person option" do
    option = billables(:two) # Lunch option
    option_table1 = Table.create!(number: 100, option: option, size: 8)
    option_table2 = Table.create!(number: 101, option: option, size: 8)
    
    # Create initial person option with table1
    person_option = PersonOption.create!(person: @person, option: option, table: option_table1)
    
    # Update to table2
    patch person_url(@person), params: { 
      person: { 
        age_id: @person.age_id, 
        back: @person.back, 
        level_id: @person.level_id, 
        name: @person.name, 
        role: @person.role, 
        studio_id: @person.studio_id, 
        type: @person.type, 
        exclude_id: '',
        options: { option.id.to_s => '1' },
        option_tables: { option.id.to_s => option_table2.id.to_s }
      } 
    }
    
    assert_redirected_to person_url(@person)
    person_option.reload
    assert_equal option_table2.id, person_option.table_id
  end

  test "should clear option table assignment when blank selected" do
    option = billables(:two) # Lunch option
    option_table = Table.create!(number: 100, option: option, size: 8)
    
    # Create person option with table
    person_option = PersonOption.create!(person: @person, option: option, table: option_table)
    
    # Update with blank table selection
    patch person_url(@person), params: { 
      person: { 
        age_id: @person.age_id, 
        back: @person.back, 
        level_id: @person.level_id, 
        name: @person.name, 
        role: @person.role, 
        studio_id: @person.studio_id, 
        type: @person.type, 
        exclude_id: '',
        options: { option.id.to_s => '1' },
        option_tables: { option.id.to_s => '' }
      } 
    }
    
    assert_redirected_to person_url(@person)
    person_option.reload
    assert_nil person_option.table_id
  end

  test "should show return_to link in edit form" do
    table = tables(:one)
    get edit_person_url(@person, return_to: edit_table_path(table))
    assert_response :success
    assert_select "a[href=?]", edit_table_path(table), text: "Back to Table"
  end

  test "should redirect to return_to URL after update" do
    table = tables(:one)
    patch person_url(@person), params: { 
      person: { 
        age_id: @person.age_id, 
        back: @person.back, 
        level_id: @person.level_id, 
        name: @person.name, 
        role: @person.role, 
        studio_id: @person.studio_id, 
        type: @person.type, 
        exclude_id: ''
      },
      return_to: edit_table_url(table)
    }
    
    assert_redirected_to edit_table_url(table)
    assert_equal flash[:notice], 'Arthur Murray was successfully updated.'
  end
  
  test "package view should show people with package-included options and seat them at table" do
    # Create a package with an option included
    package = Billable.create!(type: 'Package', name: "Test Package #{rand(1000)}", price: 100.0)
    option = Billable.create!(type: 'Option', name: "Test Option #{rand(1000)}", price: 25.0)
    PackageInclude.create!(package: package, option: option)
    
    # Create a person with this package
    studio = studios(:one)
    person = Person.create!(name: 'Package, Person', type: 'Student', studio: studio, package: package, level: levels(:FS), age: ages(:A))
    
    # Create table and seat person at table (create PersonOption record)
    table = Table.create!(number: 99, option: option, size: 10)
    PersonOption.create!(person: person, option: option, table: table)
    
    # View the option's package page
    get people_package_url(option.id)
    assert_response :success
    
    # Person should appear in the list
    assert_select "a", text: /Package, Person/
    
    # Person should NOT be in the strikethrough list (they have a PersonOption record from being seated)
    assert_select "td.line-through a", text: /Package, Person/, count: 0
  end
  
  test "package view should not strike through people seated at tables" do
    # Create an option
    option = Billable.create!(type: 'Option', name: "Test Option #{rand(1000)}", price: 25.0)
    
    # Create a person without package (direct selection)
    studio = studios(:one)
    person = Person.create!(name: 'Direct, Person', type: 'Student', studio: studio, level: levels(:FS), age: ages(:A))
    
    # Create table and seat person
    table = Table.create!(number: 99, option: option, size: 10)
    PersonOption.create!(person: person, option: option, table: table)
    
    # View the option's package page
    get people_package_url(option.id)
    assert_response :success
    
    # Person should appear in the list
    assert_select "a", text: /Direct, Person/
    
    # Person should NOT be in the strikethrough list (they have a PersonOption record)
    assert_select "td.line-through a", text: /Direct, Person/, count: 0
  end
  
  test "package view should strike through people with package access but no PersonOption record" do
    # Create an option and package that includes it
    option = Billable.create!(type: 'Option', name: "Test Option #{rand(1000)}", price: 25.0)
    package = Billable.create!(type: 'Package', name: "Test Package #{rand(1000)}", price: 100.0)
    PackageInclude.create!(package: package, option: option)
    
    # Create a person with the package (so they have access to the option)
    studio = studios(:one) 
    person = Person.create!(name: 'Package, Person', type: 'Student', studio: studio, package: package, level: levels(:FS), age: ages(:A))
    
    # View the option's package page
    get people_package_url(option.id)
    assert_response :success
    
    # Person should appear in the list since they have access through package
    assert_select "a", text: /Package, Person/

    # Person should be struck through since they don't have a PersonOption record (not seated at table)
    # The line-through class is on the td element, not the a element
    assert_select "td.line-through a", text: /Package, Person/
  end

  test "should delete answers when option is removed" do
    person = people(:Kathryn)
    lunch_option = billables(:two)
    question = questions(:meal_choice)

    # Kathryn already has answers in fixtures, verify they exist
    initial_answer_count = person.answers.count
    assert initial_answer_count > 0, "Person should have existing answers"
    assert person.answers.exists?(question: question), "Person should have answer for meal choice"

    # Verify Kathryn has the lunch option via PersonOption
    assert person.options.exists?(option_id: lunch_option.id), "Person should have lunch option"

    # Update person, removing all options (by passing empty options hash)
    patch person_url(person), params: {
      person: {
        name: person.name,
        studio_id: person.studio_id,
        type: person.type,
        level_id: person.level_id,
        age_id: person.age_id,
        role: person.role,
        options: {} # Empty options means all options are removed
      }
    }

    assert_response :redirect

    # Verify the answer was deleted because the option is no longer selected
    person.reload
    assert_equal 0, person.answers.count, "All answers should be deleted when options are removed"
  end

  # ===== UNIFIED ASSIGN_JUDGES TESTS =====

  test "assign_judges creates per-heat scores when category scoring disabled" do
    # Setup judges
    judge1 = Person.create!(name: 'Judge One', type: 'Judge', present: true, studio: studios(:one))
    judge2 = Person.create!(name: 'Judge Two', type: 'Judge', present: true, studio: studios(:one))

    # Create heats
    entry = Entry.create!(lead: people(:instructor1), follow: people(:student_one), age: ages(:one), level: levels(:one))
    heat1 = Heat.create!(number: 1, entry: entry, dance: dances(:waltz), category: 'Closed')
    heat2 = Heat.create!(number: 2, entry: entry, dance: dances(:tango), category: 'Closed')

    # Ensure category scoring is disabled
    Event.first.update!(student_judge_assignments: false)

    post assign_judges_person_path(judge1)

    assert_redirected_to person_path(judge1)

    # Should create per-heat scores (positive heat_id)
    scores = Score.heat_scores
    assert scores.count > 0, "Should create per-heat scores"
    assert_equal 0, Score.category_scores.count, "Should not create category scores"
  end

  test "assign_judges creates category scores when both flags enabled" do
    # Setup event and category with category scoring enabled
    event = Event.first
    event.update!(student_judge_assignments: true)

    category = categories(:one)
    category.update!(use_category_scoring: true)

    # Setup judges
    judge1 = Person.create!(name: 'Judge One', type: 'Judge', present: true, studio: studios(:one))
    judge2 = Person.create!(name: 'Judge Two', type: 'Judge', present: true, studio: studios(:one))

    # Create students dancing together
    student1 = Person.create!(name: 'Student One', type: 'Student', studio: studios(:one))
    student2 = Person.create!(name: 'Student Two', type: 'Student', studio: studios(:one))

    # Create closed heats in this category with students
    dance_in_category = Dance.create!(name: 'Test Dance', closed_category: category, order: 1)
    entry = Entry.create!(lead: student1, follow: student2, age: ages(:one), level: levels(:one))
    Heat.create!(number: 1, entry: entry, dance: dance_in_category, category: 'Closed')
    Heat.create!(number: 2, entry: entry, dance: dance_in_category, category: 'Closed')

    post assign_judges_person_path(judge1)

    assert_redirected_to person_path(judge1)

    # Should create category scores (negative heat_id)
    category_scores = Score.category_scores
    assert category_scores.count > 0, "Should create category scores"

    # Check that heat_id is negative (category scoring)
    category_scores.each do |score|
      assert score.heat_id < 0, "Category score should have negative heat_id"
      assert_equal category.id, score.actual_category_id
      assert_not_nil score.person_id, "Category score should have person_id"
    end
  end

  test "assign_judges handles mixed categories correctly" do
    # Setup event with category scoring enabled
    event = Event.first
    event.update!(student_judge_assignments: true)

    # Category 1: category scoring enabled
    category1 = categories(:one)
    category1.update!(use_category_scoring: true)

    # Category 2: category scoring disabled
    category2 = categories(:two)
    category2.update!(use_category_scoring: false)

    # Setup judges
    judge1 = Person.create!(name: 'Judge One', type: 'Judge', present: true, studio: studios(:one))
    judge2 = Person.create!(name: 'Judge Two', type: 'Judge', present: true, studio: studios(:one))

    # Create students for category 1
    student1 = Person.create!(name: 'Student One', type: 'Student', studio: studios(:one))
    student2 = Person.create!(name: 'Student Two', type: 'Student', studio: studios(:one))
    dance1 = Dance.create!(name: 'Dance 1', closed_category: category1, order: 1)
    entry1 = Entry.create!(lead: student1, follow: student2, age: ages(:one), level: levels(:one))
    Heat.create!(number: 1, entry: entry1, dance: dance1, category: 'Closed')

    # Create heats for category 2 (per-heat scoring)
    dance2 = Dance.create!(name: 'Dance 2', closed_category: category2, order: 2)
    entry2 = Entry.create!(lead: people(:instructor1), follow: people(:student_one), age: ages(:one), level: levels(:one))
    Heat.create!(number: 2, entry: entry2, dance: dance2, category: 'Closed')

    post assign_judges_person_path(judge1)

    assert_redirected_to person_path(judge1)

    # Should have both types of scores
    assert Score.category_scores.count > 0, "Should create category scores for category 1"
    assert Score.heat_scores.count > 0, "Should create per-heat scores for category 2"
  end

  test "assign_judges with no judges present shows alert" do
    # Ensure all judges are not present
    Person.where(type: 'Judge').update_all(present: false)

    post assign_judges_person_path(@person)

    assert_redirected_to person_path(@person)
    assert_equal "No judges are marked as present.", flash[:alert]
  end

  test "assign_judges preserves student partnerships within category" do
    # Setup
    event = Event.first
    event.update!(student_judge_assignments: true)

    category = categories(:one)
    category.update!(use_category_scoring: true)

    judge1 = Person.create!(name: 'Judge One', type: 'Judge', present: true, studio: studios(:one))
    judge2 = Person.create!(name: 'Judge Two', type: 'Judge', present: true, studio: studios(:one))

    # Create two students who dance together
    student1 = Person.create!(name: 'Student One', type: 'Student', studio: studios(:one))
    student2 = Person.create!(name: 'Student Two', type: 'Student', studio: studios(:one))

    dance = Dance.create!(name: 'Test Dance', closed_category: category, order: 1)
    entry = Entry.create!(lead: student1, follow: student2, age: ages(:one), level: levels(:one))
    Heat.create!(number: 1, entry: entry, dance: dance, category: 'Closed')

    post assign_judges_person_path(judge1)

    assert_redirected_to person_path(judge1)

    # Both students should be assigned to the same judge
    score1 = Score.find_by(heat_id: -category.id, person_id: student1.id)
    score2 = Score.find_by(heat_id: -category.id, person_id: student2.id)

    assert_not_nil score1, "Student 1 should have a category score"
    assert_not_nil score2, "Student 2 should have a category score"
    assert_equal score1.judge_id, score2.judge_id, "Students dancing together should have same judge"
  end
end
