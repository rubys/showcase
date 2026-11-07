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

  # ===== DRAGGING AGENDA ROWS =====

  # Two categories, each split into two parts, with all of the first category
  # scheduled ahead of the second:  A: 1,2  A2: 3,4  B: 5,6  B2: 7,8
  def schedule_two_split_categories
    Heat.destroy_all
    CatExtension.delete_all

    @a = categories(:one)
    @b = categories(:two)
    @a.update!(split: '2')
    @b.update!(split: '2')
    @a2 = CatExtension.create!(category: @a, part: 2, order: 100, start_heat: 3)
    @b2 = CatExtension.create!(category: @b, part: 2, order: 101, start_heat: 7)

    dances(:waltz).update!(open_category: @a)
    dances(:tango).update!(open_category: @b)

    @a_heats = (1..4).map {|number| agenda_heat(number, dances(:waltz))}
    @b_heats = (5..8).map {|number| agenda_heat(number, dances(:tango))}
  end

  def agenda_heat(number, dance)
    Heat.create!(number: number, entry: Entry.first, dance: dance, category: 'Open')
  end

  def agenda_links
    doc = Nokogiri::HTML(response.body)
    doc.css('tbody[data-controller="drop"] tr td:first-child a, tbody tr td:first-child a').map(&:text).uniq
  end

  def agenda_names_with_heats
    Nokogiri::HTML(response.body).css('tbody tr').filter_map do |row|
      cells = row.css('td')
      cells[0].text.strip if cells[2]&.text.to_i.to_i > 0 && cells[0].text.strip != 'Unscheduled'
    end
  end

  def drag(source, target)
    post drop_categories_url, as: :turbo_stream, params: { source: source, target: target }
    assert_response :success
  end

  def numbers(heats)
    heats.map {|heat| heat.reload.number}
  end

  test "dragging a part between parts of another category moves its heats" do
    schedule_two_split_categories

    drag @b.id.to_s, "#{@a2.id}-2"

    assert_equal [1, 2, 5, 6], numbers(@a_heats)
    assert_equal [3, 4, 7, 8], numbers(@b_heats)

    assert_equal [@a.name, @b.name, @a2.name, @b2.name], agenda_names_with_heats
    assert_match "#{@b.name} was successfully moved", response.body
  end

  test "dragging keeps the order of heats within each row" do
    schedule_two_split_categories

    # a manual change: swap the heats in the second part of B
    @b_heats[2].update!(number: 8)
    @b_heats[3].update!(number: 7)

    drag @b.id.to_s, "#{@a2.id}-2"

    assert_equal [3, 4, 8, 7], numbers(@b_heats)
  end

  test "dragging records where each part now starts" do
    schedule_two_split_categories

    drag @b.id.to_s, "#{@a2.id}-2"

    assert_equal 5, @a2.reload.start_heat
    assert_equal 7, @b2.reload.start_heat

    assert_equal @a2, @a_heats[2].reload.dance_category
    assert_equal @b, @b_heats[1].reload.dance_category
    assert_equal @b2, @b_heats[2].reload.dance_category
  end

  test "dragging keeps the stored order in step with the page" do
    schedule_two_split_categories

    drag @b.id.to_s, "#{@a2.id}-2"

    orders = [@a, @b, @a2, @b2].map {|cat| cat.reload.order}
    assert_equal orders.sort, orders
  end

  test "locking does not change the order of the agenda" do
    schedule_two_split_categories
    drag @b.id.to_s, "#{@a2.id}-2"

    get categories_url
    unlocked = agenda_links

    Event.current.update!(locked: true)
    get categories_url

    assert_equal unlocked, agenda_links
  end

  test "redo follows the order set by dragging" do
    schedule_two_split_categories
    drag @b.id.to_s, "#{@a2.id}-2"

    post redo_categories_url
    get categories_url

    names = agenda_names_with_heats
    assert_operator names.index(@a.name), :<, names.index(@b.name)
    assert names.index(@a2.name).nil? || names.index(@b.name) < names.index(@a2.name)
  end

  test "a part can not be dragged past another part of its own category" do
    schedule_two_split_categories

    drag "#{@a2.id}-2", @a.id.to_s
    assert_match "parts of a category need to stay in sequence", response.body
    assert_equal [1, 2, 3, 4], numbers(@a_heats)

    drag @b.id.to_s, "#{@b2.id}-2"
    assert_match "parts of a category need to stay in sequence", response.body
    assert_equal [5, 6, 7, 8], numbers(@b_heats)
  end

  test "a part can be dragged down past another category" do
    schedule_two_split_categories

    drag "#{@a2.id}-2", @b.id.to_s

    assert_equal [1, 2, 5, 6], numbers(@a_heats)
    assert_equal [3, 4, 7, 8], numbers(@b_heats)
  end

  test "continued rows can be dragged" do
    Heat.destroy_all
    CatExtension.delete_all
    a, b = categories(:one), categories(:two)
    dances(:waltz).update!(open_category: a)
    dances(:tango).update!(open_category: b)
    first = agenda_heat(1, dances(:waltz))
    other = agenda_heat(2, dances(:tango))
    rest = agenda_heat(3, dances(:waltz))

    get categories_url
    assert_select "tr[draggable][data-drag-id='#{a.id}:1']"

    drag "#{a.id}:1", b.id.to_s

    assert_equal [1, 3, 2], numbers([first, other, rest])
    assert_empty agenda_links.grep(/\(continued/)
  end

  test "a continued row can not pass the rest of its category" do
    Heat.destroy_all
    CatExtension.delete_all
    a, b = categories(:one), categories(:two)
    dances(:waltz).update!(open_category: a)
    dances(:tango).update!(open_category: b)
    heats = [agenda_heat(1, dances(:waltz)), agenda_heat(2, dances(:tango)), agenda_heat(3, dances(:waltz))]

    drag "#{a.id}:1", a.id.to_s

    assert_match "need to stay in sequence", response.body
    assert_equal [1, 2, 3], numbers(heats)
  end

  test "dragging leaves other interleaved rows interleaved" do
    Heat.destroy_all
    CatExtension.delete_all
    a, b, c = categories(:one), categories(:two), categories(:three)
    dances(:waltz).update!(open_category: a)
    dances(:tango).update!(open_category: b)
    dances(:rumba).update!(open_category: c)
    heats = [
      agenda_heat(1, dances(:waltz)), agenda_heat(2, dances(:tango)),
      agenda_heat(3, dances(:waltz)), agenda_heat(4, dances(:rumba))
    ]

    drag c.id.to_s, b.id.to_s

    assert_equal [1, 3, 4, 2], numbers(heats)
    assert_includes agenda_links, "#{a.name} (continued)"
  end

  test "dragging does not restore scratched heats" do
    schedule_two_split_categories
    @b_heats[0].update!(number: -5)

    drag @b.id.to_s, "#{@a2.id}-2"

    assert_equal [-3, 4, 7, 8], numbers(@b_heats)
    assert_equal [1, 2, 5, 6], numbers(@a_heats)
  end

  test "splitting a category does not restore scratched heats" do
    Heat.destroy_all
    CatExtension.delete_all
    a = categories(:one)
    dances(:waltz).update!(open_category: a)
    heats = (1..4).map {|number| agenda_heat(number, dances(:waltz))}
    heats[1].update!(number: -2)

    patch category_url(a), params: { category: { name: a.name, order: a.order, customize: '1', split: '2' } }

    assert_equal 1, a.reload.extensions.count
    assert heats[1].reload.number.negative?, "scratched heat should stay scratched"
    assert_equal 3, heats.count {|heat| heat.reload.number.positive?}
  end

  test "dragging tidies up fractional heat numbers" do
    schedule_two_split_categories
    @b_heats[0].update!(number: 5.5)

    drag @b.id.to_s, "#{@a2.id}-2"

    assert_equal [3, 4, 7, 8], numbers(@b_heats)
  end

  test "heats that are not on the agenda follow the agenda when dragging" do
    schedule_two_split_categories
    orphan = Dance.create!(name: 'Orphan', order: 999)
    loose = agenda_heat(4.5, orphan)

    drag @b.id.to_s, "#{@a2.id}-2"

    assert_equal 9, loose.reload.number
    assert_equal [1, 2, 5, 6], numbers(@a_heats)
    assert_equal [3, 4, 7, 8], numbers(@b_heats)
  end

  test "dragging a category with no heats changes its place but not the heats" do
    schedule_two_split_categories
    empty = Category.create!(name: 'Not Yet Scheduled', order: 200)

    drag empty.id.to_s, @b.id.to_s

    assert_equal [1, 2, 3, 4], numbers(@a_heats)
    assert_equal [5, 6, 7, 8], numbers(@b_heats)

    links = agenda_links
    assert_equal links.index(@b.name) - 1, links.index(empty.name)
  end

  test "categories can be arranged before anything is scheduled" do
    Heat.update_all(number: 0)
    CatExtension.delete_all
    one, four = categories(:one), categories(:four)

    drag one.id.to_s, four.id.to_s

    assert_operator one.reload.order, :>, four.reload.order
    assert_equal Heat.count, Heat.where(number: 0).count

    links = agenda_links
    assert_operator links.index(four.name), :<, links.index(one.name)
  end

  test "breaks stay in place when other rows are dragged around them" do
    schedule_two_split_categories
    lunch = Category.create!(name: 'Lunch', order: 50, duration: 30)
    @a2.update_column(:order, 49)
    @b.update_column(:order, 51)
    @b2.update_column(:order, 52)
    @a.update_column(:order, 48)

    get categories_url
    links = agenda_links
    assert_equal links.index(@a2.name) + 1, links.index(lunch.name)
    assert_equal links.index(lunch.name) + 1, links.index(@b.name)

    drag "#{@a2.id}-2", @b.id.to_s

    # A2 moved from before the break to after B; the break still comes right before B
    links = agenda_links
    assert_equal links.index(lunch.name) + 1, links.index(@b.name)
    assert_equal links.index(@b.name) + 1, links.index(@a2.name)
    assert_equal [1, 2, 5, 6], numbers(@a_heats)
  end

  test "dragging is refused when the agenda is locked" do
    schedule_two_split_categories
    Event.current.update!(locked: true)

    drag @b.id.to_s, "#{@a2.id}-2"

    assert_match "locked", response.body
    assert_equal [5, 6, 7, 8], numbers(@b_heats)
  end

  test "dragging a row that no longer exists is reported" do
    schedule_two_split_categories

    drag "#{@a.id}:5", @b.id.to_s

    assert_match "please try again", response.body
    assert_equal [1, 2, 3, 4], numbers(@a_heats)
  end

  test "should destroy category" do
    assert_difference("Category.count", -1) do
      delete category_url(@category)
    end

    assert_response 303
    assert_redirected_to categories_url
    assert_equal flash[:notice], 'Closed American Smooth was successfully removed.'
  end

  # ===== DRAG AND DROP LOCK TESTS =====

  test "should disable drag and drop when event is locked" do
    # Lock the event
    Event.current.update(locked: true)

    get categories_url

    assert_response :success

    # Verify tbody doesn't have drop controller
    assert_select 'tbody[data-controller="drop"]', count: 0

    # Verify main category rows are not draggable
    doc = Nokogiri::HTML(response.body)
    main_rows = doc.css('tbody tr[draggable="true"]')
    assert_equal 0, main_rows.length, "No rows should be draggable when locked"

    # Verify continued rows don't have data-droppable
    continued_rows = doc.css('tbody tr[data-droppable]')
    assert_equal 0, continued_rows.length, "No rows should have data-droppable when locked"
  end

  test "should enable drag and drop when event is unlocked" do
    # Ensure event is unlocked
    Event.current.update(locked: false)

    get categories_url

    assert_response :success

    # Verify tbody has drop controller
    assert_select 'tbody[data-controller="drop"]', count: 1

    # Verify main category rows are draggable
    doc = Nokogiri::HTML(response.body)
    main_rows = doc.css('tbody tr[draggable="true"]')
    assert main_rows.length > 0, "Some rows should be draggable when unlocked"
  end

  test "unlocked event should display categories in the same order as locked" do
    Event.current.update(locked: false)

    get categories_url
    assert_response :success
    unlocked = Nokogiri::HTML(response.body).css('tbody tr td:first-child a').map(&:text)

    Event.current.update(locked: true)

    get categories_url
    assert_response :success
    locked = Nokogiri::HTML(response.body).css('tbody tr td:first-child a').map(&:text)

    assert_equal locked, unlocked
  end

  test "locked event should display categories in agenda order matching heats page" do
    Event.current.update(locked: true)

    get categories_url
    assert_response :success

    # Extract category names (excluding Unscheduled/Uncategorized)
    doc = Nokogiri::HTML(response.body)
    categories_displayed = doc.css('tbody tr td:first-child a').map(&:text)
    categories_displayed.reject! { |name| %w[Unscheduled Uncategorized].include?(name) }

    # Get the heats page order for comparison
    get heats_url
    assert_response :success

    heats_doc = Nokogiri::HTML(response.body)
    heats_displayed = heats_doc.css('table tr td:first-child a').map(&:text)
    heats_displayed.reject! { |name| %w[Unscheduled Uncategorized].include?(name) }

    # Categories that appear on both pages should be in the same order
    common = categories_displayed & heats_displayed
    categories_common = categories_displayed.select { |c| common.include?(c) }
    heats_common = heats_displayed.select { |c| common.include?(c) }

    assert_equal heats_common, categories_common,
      "Locked: categories should display in same order as heats page (agenda order)"
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

  # ===== BREAK AND WARM-UP DURATION TESTS =====

  test "categories with duration but no heats should display times" do
    # Clear existing heats, extensions, and categories first
    Heat.destroy_all
    CatExtension.destroy_all
    # Clear dance category references before destroying categories
    Dance.update_all(
      open_category_id: nil, closed_category_id: nil, solo_category_id: nil, multi_category_id: nil,
      pro_open_category_id: nil, pro_closed_category_id: nil, pro_solo_category_id: nil, pro_multi_category_id: nil
    )
    Category.destroy_all

    # Set up event with date and heat_length for time calculations
    # Do this after clearing categories to avoid any caching issues
    event = Event.first || Event.create!
    event.update!(date: '2025-11-08', heat_length: 75, include_times: true)

    # Create categories: WARM-UP (20 min), SMOOTH (with heats), BREAK (15 min), RHYTHM (with heats)
    warmup = Category.create!(name: 'WARM-UP', order: 1, time: '10:00', duration: 20)
    smooth = Category.create!(name: 'SMOOTH', order: 2)
    break_cat = Category.create!(name: 'BREAK', order: 3, duration: 15)
    rhythm = Category.create!(name: 'RHYTHM', order: 4)

    # Create heats only for SMOOTH and RHYTHM
    waltz = dances(:waltz)
    tango = dances(:tango)
    waltz.update!(open_category: smooth)
    tango.update!(open_category: rhythm)

    entry = Entry.first
    age = ages(:one)
    level = levels(:one)
    entry.update!(age: age, level: level)

    Heat.create!(number: 1, entry: entry, dance: waltz, category: 'Open')
    Heat.create!(number: 2, entry: entry, dance: tango, category: 'Open')

    get categories_url

    assert_response :success

    doc = Nokogiri::HTML(response.body)

    # Find WARM-UP row
    warmup_row = doc.css('tbody tr').find { |row| row.css('td a').text == 'WARM-UP' }
    assert_not_nil warmup_row, "WARM-UP category should appear in agenda"

    # WARM-UP should have time columns even with 0 heats
    warmup_cells = warmup_row.css('td').map(&:text).map(&:strip)

    # Debug: check if we have enough cells (should be at least 5: name, entries, heats, start, end)
    assert warmup_cells.length >= 4, "WARM-UP should have at least 4 cells (name, entries, heats, times), got: #{warmup_cells.inspect}"

    # First cell is the category name link
    assert_equal 'WARM-UP', warmup_cells[0]
    assert_equal '0', warmup_cells[1], "WARM-UP should show 0 entries"
    assert_equal '0', warmup_cells[2], "WARM-UP should show 0 heats"

    # Time columns should exist
    assert_match /10:00/, warmup_cells[3] || '', "WARM-UP should show start time"
    assert_match /10:20/, warmup_cells[4] || '', "WARM-UP should show end time (start + 20 min)"

    # Find BREAK row
    break_row = doc.css('tbody tr').find { |row| row.css('td a').text == 'BREAK' }
    assert_not_nil break_row, "BREAK category should appear in agenda"

    # BREAK should have time columns
    break_cells = break_row.css('td').map(&:text).map(&:strip)
    assert_equal '0', break_cells[1], "BREAK should show 0 entries"
    assert_equal '0', break_cells[2], "BREAK should show 0 heats"
    assert_match /\d+:\d+/, break_cells[3], "BREAK should show start time"
    assert_match /\d+:\d+/, break_cells[4], "BREAK should show end time"
  end

  test "categories with duration should appear in correct order" do
    # Set up event with date and heat_length
    event = Event.current
    event.update!(date: '2025-11-08', heat_length: 75, include_times: true)

    # Clear existing heats and categories
    Heat.destroy_all
    Category.destroy_all

    # Create categories in specific order
    warmup = Category.create!(name: 'WARM-UP', order: 1, time: '10:00', duration: 20)
    smooth = Category.create!(name: 'SMOOTH', order: 2)
    break1 = Category.create!(name: 'BREAK 1', order: 3, duration: 15)
    rhythm = Category.create!(name: 'RHYTHM', order: 4)
    break2 = Category.create!(name: 'BREAK 2', order: 5, duration: 10)

    # Create heats for SMOOTH and RHYTHM
    waltz = dances(:waltz)
    tango = dances(:tango)
    waltz.update!(open_category: smooth)
    tango.update!(open_category: rhythm)

    entry = Entry.first
    entry.update!(age: ages(:one), level: levels(:one))

    Heat.create!(number: 1, entry: entry, dance: waltz, category: 'Open')
    Heat.create!(number: 2, entry: entry, dance: tango, category: 'Open')

    get categories_url

    assert_response :success

    # Extract category names in order
    category_names = []
    assert_select 'tbody tr td:first-child a' do |links|
      category_names = links.map(&:text).reject { |name| name == 'Unscheduled' }
    end

    # Verify order: WARM-UP, SMOOTH, BREAK 1, RHYTHM, BREAK 2
    assert_includes category_names, 'WARM-UP'
    assert_includes category_names, 'BREAK 1'
    assert_includes category_names, 'BREAK 2'

    warmup_idx = category_names.index('WARM-UP')
    smooth_idx = category_names.index('SMOOTH')
    break1_idx = category_names.index('BREAK 1')
    rhythm_idx = category_names.index('RHYTHM')
    break2_idx = category_names.index('BREAK 2')

    assert warmup_idx < smooth_idx, "WARM-UP should come before SMOOTH"
    assert smooth_idx < break1_idx, "SMOOTH should come before BREAK 1"
    assert break1_idx < rhythm_idx, "BREAK 1 should come before RHYTHM"
    assert rhythm_idx < break2_idx, "RHYTHM should come before BREAK 2"
  end

  test "break after heats should start after last heat finishes" do
    # Set up event
    event = Event.current
    event.update!(date: '2025-11-08', heat_length: 75, include_times: true)

    Heat.destroy_all
    Category.destroy_all

    smooth = Category.create!(name: 'SMOOTH', order: 1, time: '10:00')
    break_cat = Category.create!(name: 'BREAK', order: 2, duration: 15)
    rhythm = Category.create!(name: 'RHYTHM', order: 3)

    waltz = dances(:waltz)
    tango = dances(:tango)
    waltz.update!(open_category: smooth)
    tango.update!(open_category: rhythm)

    entry = Entry.first
    entry.update!(age: ages(:one), level: levels(:one))

    # Create a heat in SMOOTH
    Heat.create!(number: 1, entry: entry, dance: waltz, category: 'Open')
    Heat.create!(number: 2, entry: entry, dance: tango, category: 'Open')

    get categories_url

    assert_response :success

    doc = Nokogiri::HTML(response.body)

    smooth_row = doc.css('tbody tr').find { |row| row.css('td a').text == 'SMOOTH' }
    break_row = doc.css('tbody tr').find { |row| row.css('td a').text == 'BREAK' }
    rhythm_row = doc.css('tbody tr').find { |row| row.css('td a').text == 'RHYTHM' }

    # Extract finish time of SMOOTH
    smooth_finish = smooth_row.css('td')[4]&.text&.strip

    # Extract start time of BREAK
    break_start = break_row.css('td')[3]&.text&.strip

    # Extract end time of BREAK
    break_end = break_row.css('td')[4]&.text&.strip

    # Extract start time of RHYTHM
    rhythm_start = rhythm_row.css('td')[3]&.text&.strip

    # BREAK should start when SMOOTH finishes
    assert_equal smooth_finish, break_start, "BREAK should start when SMOOTH finishes"

    # RHYTHM should start when BREAK ends
    assert_equal break_end, rhythm_start, "RHYTHM should start when BREAK ends"
  end
  test "removing a split dance referenced as a solo combo dance" do
    event = Event.current
    event.update!(agenda_based_entries: true)
    @category.update!(routines: true)

    split = Dance.create!(name: 'Tango', solo_category: @category, order: -1)
    solo = solos(:one)
    solo.update!(combo_dance: split)

    patch category_url(@category), params: { category: {
      name: @category.name,
      order: @category.order,
      time: @category.time,
      routines: '1',
      pro: '0',
      include: {'Solo' => {'Tango' => '0'}}
    } }

    assert_redirected_to categories_url
    assert_nil Dance.find_by(id: split.id)
    assert_equal dances(:tango), solo.reload.combo_dance
  end
end
