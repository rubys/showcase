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

  test "should not show table options for Judge in edit" do
    judge = people(:Judy)
    get edit_person_url(judge)
    assert_response :success
    assert_no_match /Table \d+ -/, response.body
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
    assert_select "a[href=?]", edit_table_path(table), text: "Back to table"
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
end
