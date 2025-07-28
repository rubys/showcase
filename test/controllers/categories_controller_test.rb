require "test_helper"

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @category = categories(:one)
  end

  test "should get index" do
    get categories_url
    assert_response :success
  end

  test "should get new" do
    get new_category_url
    assert_response :success
  end

  test "should create category" do
    assert_difference("Category.count") do
      post categories_url, params: { category: {
        name: @category.name + " Part II",
        order: @category.order,
        time: @category.time,
        include: {
          'Open' => {'Waltz' => 0, 'Tango' => 1},
          'Closed' => {'Waltz' => 1, 'Tango' => 0},
          'Solo' => {'Waltz' => 1, 'Tango' => 0},
          'Multi' => {'All Around Smooth' => 0}
        }
      } }
    end

    waltz = Dance.find_by(name: 'Waltz')
    tango = Dance.find_by(name: 'Tango')

    newcat = Category.last

    assert_equal newcat, waltz.closed_category
    assert_equal categories(:two), waltz.open_category
    assert_equal categories(:one), tango.closed_category
    assert_equal newcat, tango.open_category

    assert_redirected_to categories_url
    assert_equal flash[:notice], 'Closed American Smooth Part II was successfully created.'
  end

  test "should show category" do
    get category_url(@category)
    assert_response :success
  end

  test "should get edit" do
    get edit_category_url(@category)
    assert_response :success
    assert_select 'a[data-turbo-method=delete]', 'Remove this category'
  end

  test "should update category" do
    patch category_url(@category), params: { category: {
      name: @category.name,
      order: @category.order,
      time: @category.time,
      include: {
        'Open' => {'Waltz' => 0, 'Tango' => 1},
        'Closed' => {'Waltz' => 1, 'Tango' => 0},
        'Solo' => {'Waltz' => 1, 'Tango' => 0},
        'Multi' => {'All Around Smooth' => 0}
      }
    } }

    waltz = Dance.find_by(name: 'Waltz')
    tango = Dance.find_by(name: 'Tango')

    assert_equal categories(:one), waltz.closed_category
    assert_equal categories(:two), waltz.open_category
    assert_nil tango.closed_category
    assert_equal categories(:one), tango.open_category

    assert_redirected_to categories_url
    assert_equal flash[:notice], 'Closed American Smooth was successfully updated.'
  end

  test "should reorder categories" do
    get categories_url

    assert_response :success

    assert_select 'tr td:first-child a' do |links|
      assert_equal [
        "Unscheduled",
        "Closed American Smooth",
        "Open American Smooth - Part 1",
        "Closed American Smooth - Part 1",
        "Closed American Rhythm",
        "All Arounds",
        "Open American Smooth",
        "Open American Rhythm",
        "Solos"
      ], links.map(&:text)
    end

    post drop_categories_url, as: :turbo_stream, params: {
      source: categories(:one).id,
      target: categories(:four).id
    }

    assert_response :success

    assert_select 'tr td:first-child a' do |links|
      assert_equal [
        "Closed American Rhythm",
        "Open American Smooth - Part 1",
        "Closed American Smooth - Part 1",
        "All Arounds",
        "Open American Smooth",
        "Open American Rhythm",
        "Closed American Smooth",
        "Solos"
      ], links.map(&:text)
    end

    assert_equal 1, categories(:one).order
    categories(:one).reload
    assert_equal 5, categories(:one).order
  end

  test "should destroy category" do
    assert_difference("Category.count", -1) do
      delete category_url(@category)
    end

    assert_response 303
    assert_redirected_to categories_url
    assert_equal flash[:notice], 'Closed American Smooth was successfully removed.'
  end
end
