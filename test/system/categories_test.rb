require "application_system_test_case"

class CategoriesTest < ApplicationSystemTestCase
  setup do
    @category = categories(:one)
  end

  test "visiting the index" do
    visit categories_url
    assert_selector "h1", text: "Agenda"
  end

  test "should create category" do
    visit categories_url
    click_on "New category"

    fill_in "Name", with: @category.name + ' Part II'
    fill_in "Time", with: Chronic.parse(@category.time)
    click_on "Create Category"

    assert_text "Closed American Smooth Part II was successfully created"
    click_on "Back"
  end

  test "should update Category" do
    visit category_url(@category)
    click_on "Edit this category", match: :first

    fill_in "Name", with: @category.name
    fill_in "Time", with: @category.time
    click_on "Update Category"

    assert_text "Closed American Smooth was successfully updated"
    click_on "Back"
  end

  test "should destroy Category" do
    visit category_url(@category)
    click_on "Destroy this category", match: :first

    assert_text "Closed American Smooth was successfully removed"
  end

  test "dragging an agenda row moves its heats" do
    Heat.destroy_all
    CatExtension.delete_all

    first = categories(:one)
    second = categories(:two)
    first.update!(split: '2')
    part = CatExtension.create!(category: first, part: 2, order: 100, start_heat: 3)

    dances(:waltz).update!(open_category: first)
    dances(:tango).update!(open_category: second)

    entry = Entry.first
    first_heats = (1..4).map {|number| Heat.create!(number: number, entry: entry, dance: dances(:waltz), category: 'Open')}
    second_heats = (5..6).map {|number| Heat.create!(number: number, entry: entry, dance: dances(:tango), category: 'Open')}

    # the drop controller sends the page's CSRF token, which is only rendered
    # when forgery protection is on
    ActionController::Base.allow_forgery_protection = true

    visit categories_url

    source = find("tr[data-drag-id='#{second.id}']")
    target = find("tr[data-drag-id='#{part.id}-2']")
    source.drag_to(target, html5: true)

    assert_text "#{second.name} was successfully moved"

    assert_equal [1, 2, 5, 6], first_heats.map {|heat| heat.reload.number}
    assert_equal [3, 4], second_heats.map {|heat| heat.reload.number}
    assert_equal 5, part.reload.start_heat

    # the list was replaced, so dragging needs to work a second time
    assert_selector "tr[data-drag-id='#{second.id}'] + tr[data-drag-id='#{part.id}-2']"
    find("tr[data-drag-id='#{part.id}-2']").drag_to(find("tr[data-drag-id='#{first.id}']"), html5: true)
    assert_text "need to stay in sequence"
  ensure
    ActionController::Base.allow_forgery_protection = false
  end
end
