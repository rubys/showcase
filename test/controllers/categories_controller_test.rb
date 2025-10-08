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
        "Closed American Smooth (continued)",
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
        "Open American Smooth (continued)",
        "Open American Rhythm",
        "Closed American Smooth",
        "Closed American Smooth (continued)",
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

  # ===== CONTINUED CATEGORY PLACEMENT TESTS =====

  test "should show continued category sections when categories are interleaved" do
    # Clear existing heats
    Heat.destroy_all

    cat1 = categories(:one)
    max_order = Category.maximum(:order) || 0
    cat2 = Category.create!(name: 'Second Category', order: max_order + 1)

    waltz = dances(:waltz)
    tango = dances(:tango)
    rumba = dances(:rumba)

    waltz.update!(solo_category: cat1)
    tango.update!(solo_category: cat2)
    rumba.update!(solo_category: cat1)

    entry = Entry.first
    age = ages(:one)
    level = levels(:one)
    entry.update!(age: age, level: level)

    # Create heats: cat1, cat1, cat2, cat1 (cat1 is split by cat2)
    heat55 = Heat.create!(number: 55, entry: entry, dance: waltz, category: 'Solo')
    heat56 = Heat.create!(number: 56, entry: entry, dance: waltz, category: 'Solo')
    heat57 = Heat.create!(number: 57, entry: entry, dance: tango, category: 'Solo')
    heat58 = Heat.create!(number: 58, entry: entry, dance: rumba, category: 'Solo')

    # Create solo records
    max_order = Solo.maximum(:order) || 0
    Solo.create!(heat: heat55, order: max_order + 1)
    Solo.create!(heat: heat56, order: max_order + 2)
    Solo.create!(heat: heat57, order: max_order + 3)
    Solo.create!(heat: heat58, order: max_order + 4)

    get categories_url

    assert_response :success

    # Should show main category and continued section
    assert_select 'tr td:first-child a', text: cat1.name
    assert_select 'tr td:first-child a', text: /#{cat1.name} \(continued/
  end

  test "continued sections should be indented" do
    # Clear existing heats
    Heat.destroy_all

    cat1 = categories(:one)
    max_order = Category.maximum(:order) || 0
    cat2 = Category.create!(name: 'Second Category', order: max_order + 1)

    waltz = dances(:waltz)
    tango = dances(:tango)

    waltz.update!(solo_category: cat1)
    tango.update!(solo_category: cat2)

    entry = Entry.first
    age = ages(:one)
    level = levels(:one)
    entry.update!(age: age, level: level)

    # Create heats: cat1, cat2, cat1 (cat1 is split by cat2)
    heat10 = Heat.create!(number: 10, entry: entry, dance: waltz, category: 'Solo')
    heat20 = Heat.create!(number: 20, entry: entry, dance: tango, category: 'Solo')
    heat30 = Heat.create!(number: 30, entry: entry, dance: waltz, category: 'Solo')

    max_order = Solo.maximum(:order) || 0
    Solo.create!(heat: heat10, order: max_order + 1)
    Solo.create!(heat: heat20, order: max_order + 2)
    Solo.create!(heat: heat30, order: max_order + 3)

    get categories_url

    assert_response :success

    # Check for indented continued section (pl-8 class)
    assert_select 'tr td.pl-8 a', text: /#{cat1.name} \(continued/
  end

  test "continued sections should appear underneath main category" do
    # Clear existing heats
    Heat.destroy_all

    cat1 = categories(:one)
    max_order = Category.maximum(:order) || 0
    cat2 = Category.create!(name: 'Second Category', order: max_order + 1)

    waltz = dances(:waltz)
    tango = dances(:tango)
    rumba = dances(:rumba)

    waltz.update!(solo_category: cat1)
    tango.update!(solo_category: cat2)
    rumba.update!(solo_category: cat1)

    entry = Entry.first
    age = ages(:one)
    level = levels(:one)
    entry.update!(age: age, level: level)

    # Create heats: cat1, cat2, cat1 (cat1 is split by cat2)
    heat5 = Heat.create!(number: 5, entry: entry, dance: waltz, category: 'Solo')
    heat10 = Heat.create!(number: 10, entry: entry, dance: tango, category: 'Solo')
    heat15 = Heat.create!(number: 15, entry: entry, dance: rumba, category: 'Solo')

    max_order = Solo.maximum(:order) || 0
    Solo.create!(heat: heat5, order: max_order + 1)
    Solo.create!(heat: heat10, order: max_order + 2)
    Solo.create!(heat: heat15, order: max_order + 3)

    get categories_url

    assert_response :success

    # Get all category links in order
    links = []
    assert_select 'tr td:first-child a' do |elements|
      links = elements.map(&:text)
    end

    # Find indices - continued section should appear directly after main category
    main_idx = links.index(cat1.name)
    continued_idx = links.index { |text| text.include?("#{cat1.name} (continued") }

    # Verify both exist and continued appears after main
    assert_not_nil main_idx, "Main category should exist"
    assert_not_nil continued_idx, "Continued section should exist"
    assert main_idx < continued_idx, "Continued section should appear after main category"

    # Verify continued is directly after main (with no other categories in between from same base)
    between = links[(main_idx + 1)...continued_idx]
    assert between.none? { |link| link.start_with?(cat1.name) && !link.include?("(continued") },
      "No other #{cat1.name} entries should appear between main and continued"
  end

  test "continued sections should show correct heat counts" do
    # Clear existing heats
    Heat.destroy_all

    cat1 = categories(:one)
    max_order = Category.maximum(:order) || 0
    cat2 = Category.create!(name: 'Second Category', order: max_order + 1)

    waltz = dances(:waltz)
    tango = dances(:tango)

    waltz.update!(solo_category: cat1)
    tango.update!(solo_category: cat2)

    entry = Entry.first
    age = ages(:one)
    level = levels(:one)
    entry.update!(age: age, level: level)

    # Create heats: cat1 (2 heats), cat2 (1 heat), cat1 (1 heat)
    heat5 = Heat.create!(number: 5, entry: entry, dance: waltz, category: 'Solo')
    heat6 = Heat.create!(number: 6, entry: entry, dance: waltz, category: 'Solo')
    heat7 = Heat.create!(number: 7, entry: entry, dance: tango, category: 'Solo')
    heat8 = Heat.create!(number: 8, entry: entry, dance: waltz, category: 'Solo')

    max_order = Solo.maximum(:order) || 0
    Solo.create!(heat: heat5, order: max_order + 1)
    Solo.create!(heat: heat6, order: max_order + 2)
    Solo.create!(heat: heat7, order: max_order + 3)
    Solo.create!(heat: heat8, order: max_order + 4)

    get categories_url

    assert_response :success

    # Parse the response to find heat counts
    doc = Nokogiri::HTML(response.body)
    rows = doc.css('tbody[data-controller="drop"] tr')

    main_row = rows.find { |row| row.css('td:first-child a').text == cat1.name }
    continued_row = rows.find { |row| row.css('td:first-child a').text.include?("#{cat1.name} (continued") }

    if main_row && continued_row
      # Get the heat count from the third column (Heats column)
      main_heat_count = main_row.css('td')[2]&.text&.to_i
      continued_heat_count = continued_row.css('td')[2]&.text&.to_i

      assert_equal 2, main_heat_count, "Main section should show 2 heats"
      assert_equal 1, continued_heat_count, "Continued section should show 1 heat"
    end
  end

  test "continued sections should link to same category as main section" do
    # Clear existing heats
    Heat.destroy_all

    cat1 = categories(:one)
    max_order = Category.maximum(:order) || 0
    cat2 = Category.create!(name: 'Second Category', order: max_order + 1)

    waltz = dances(:waltz)
    tango = dances(:tango)

    waltz.update!(solo_category: cat1)
    tango.update!(solo_category: cat2)

    entry = Entry.first
    age = ages(:one)
    level = levels(:one)
    entry.update!(age: age, level: level)

    # Create heats: cat1, cat2, cat1
    heat10 = Heat.create!(number: 10, entry: entry, dance: waltz, category: 'Solo')
    heat20 = Heat.create!(number: 20, entry: entry, dance: tango, category: 'Solo')
    heat30 = Heat.create!(number: 30, entry: entry, dance: waltz, category: 'Solo')

    max_order = Solo.maximum(:order) || 0
    Solo.create!(heat: heat10, order: max_order + 1)
    Solo.create!(heat: heat20, order: max_order + 2)
    Solo.create!(heat: heat30, order: max_order + 3)

    get categories_url

    assert_response :success

    # Check that both link to the same category edit path
    doc = Nokogiri::HTML(response.body)
    main_link = doc.css('tbody[data-controller="drop"] tr td:first-child a').find { |a| a.text == cat1.name }
    continued_link = doc.css('tbody[data-controller="drop"] tr td:first-child a').find { |a| a.text.include?("#{cat1.name} (continued") }

    if main_link && continued_link
      main_href = main_link['href']
      continued_href = continued_link['href']

      assert_equal main_href, continued_href, "Main and continued sections should link to same category"
      assert_match /\/categories\/#{cat1.id}\/edit/, main_href
    end
  end
end
