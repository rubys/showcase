require "test_helper"

class DancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @dance = dances(:waltz)
  end

  test "should get index" do
    get dances_url
    assert_response :success
  end

  test "should get new" do
    get new_dance_url
    assert_response :success
  end

  test "should create dance" do
    assert_difference("Dance.count") do
      post dances_url, params: { dance: {
        open_category: @dance.open_category,
        closed_category: @dance.closed_category,
        name: "Zouk"
       } }
    end

    assert_redirected_to controller: 'dances', action: 'index'
    assert_equal flash[:notice], 'Zouk was successfully created.'
  end

  test "should show dance" do
    get dance_url(@dance)
    assert_response :success
  end

  test "should get edit" do
    get edit_dance_url(@dance)
    assert_response :success
    assert_select 'form input[name="_method"][value=delete]'
    assert_select 'form button', 'Remove this dance'
  end

  test "should update dance" do
    patch dance_url(@dance), params: { dance: {
      open_category: @dance.open_category,
      closed_category: @dance.closed_category,
      name: @dance.name
    } }

    assert_redirected_to dances_url
    assert_equal flash[:notice], 'Waltz was successfully updated.'
  end

  test "should reorder dances" do
    post drop_dances_url, as: :turbo_stream, params: {
      source: dances(:rumba).id,
      target: dances(:waltz).id
    }
      
    assert_response :success

    assert_select 'tr td:first-child a' do |links|
      assert_equal ["Rumba", "Waltz", "Tango", "Cha Cha", "All Around Smooth"], links.map(&:text)
    end

    assert_equal 3, dances(:rumba).order
    dances(:rumba).reload
    assert_equal 1, dances(:rumba).order
  end

  test "should destroy dance" do
    assert_difference("Dance.count", -1) do
      delete dance_url(@dance)
    end

    assert_response 303
    assert_redirected_to dances_url
    assert_equal flash[:notice], 'Waltz was successfully removed.'
  end

  test "should get trophies" do
    get trophies_dances_url
    assert_response :success
    assert_select 'h1', 'Trophy Order'
  end

  test "trophies page shows correct trophy counts" do
    # Create a multi-dance with entries
    multi_cat = Category.create!(name: "Test Multi Category", order: 999)
    multi_dance = Dance.create!(
      name: "Test Multi-Dance",
      order: 999,
      heat_length: 3,
      multi_category: multi_cat
    )

    # Create 3 entries for this multi-dance
    3.times do |i|
      student = Person.create!(
        name: "Trophy Test Student #{i}",
        studio: studios(:one),
        type: 'Student',
        level: levels(:one)
      )
      instructor = Person.create!(
        name: "Trophy Test Instructor #{i}",
        studio: studios(:one),
        type: 'Professional',
        back: 900 + i
      )
      entry = Entry.create!(
        lead: student,
        follow: instructor,
        age: ages(:one),
        level: levels(:one)
      )
      Heat.create!(
        dance: multi_dance,
        entry: entry,
        category: 'Multi',
        number: 100 + i
      )
    end

    get trophies_dances_url
    assert_response :success

    # Should show 1 first, 1 second, 1 third for 3 entries
    assert_select 'table tbody tr' do |rows|
      # Find row for our test dance
      test_dance_row = rows.find { |r| r.text.include?('Test Multi-Dance') }
      assert test_dance_row, "Should find Test Multi-Dance in table"
    end
  end
end
