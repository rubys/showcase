require "test_helper"

class ScoreTabulatorTest < ActiveSupport::TestCase
  setup do
    @event = events(:one)
    Event.current = @event
  end

  def tabulator(**attrs)
    @event.assign_attributes(attrs)
    ScoreTabulator.new(@event)
  end

  # ===== BUCKET LAYOUT =====

  test "open and closed each get a bucket when they are scored separately" do
    t = tabulator(open_scoring: '1', closed_scoring: 'G')

    assert_equal %w(Closed Open), t.buckets.map(&:category)
    assert_equal %w(GH G S B), t.bucket_for('Closed').headers
    assert_equal %w(1 2 3 F), t.bucket_for('Open').headers
    assert t.labeled?
  end

  test "a single bucket when closed scoring is same as open" do
    t = tabulator(open_scoring: 'G', closed_scoring: '=')

    assert_equal %w(Open), t.buckets.map(&:category)
    assert_equal 'Open', t.bucket_for('Closed').category
    assert_not t.labeled?
  end

  test "a single bucket when open and closed heats are combined" do
    t = tabulator(open_scoring: '1', closed_scoring: 'G', heat_range_cat: 1)

    assert_equal %w(Open), t.buckets.map(&:category)
    assert_equal %w(1 2 3 F), t.bucket_for('Closed').headers
  end

  test "number and feedback styles contribute no columns" do
    %w(# + @).each do |style|
      t = tabulator(open_scoring: style, closed_scoring: '=')
      assert_empty t.bucket_for('Open').headers, "expected no columns for #{style}"
      assert_not t.columns?, "expected no columns for #{style}"
    end
  end

  # ===== NUMBER (1-5) AND FEEDBACK =====

  test "closed scoring of number and feedback gets five columns, best first" do
    t = tabulator(open_scoring: '1', closed_scoring: '&')

    assert_equal %w(5 4 3 2 1), t.bucket_for('Closed').headers
    assert_equal %w(1 2 3 F), t.bucket_for('Open').headers
    assert t.columns?
  end

  test "a closed five is the best score and a one is the worst" do
    t = tabulator(open_scoring: '1', closed_scoring: '&')

    best = t.tabulate('5', 'Closed')
    assert_equal 'Closed', best[:category]
    assert_equal 0, best[:index]
    assert_equal 5, best[:points]

    worst = t.tabulate('1', 'Closed')
    assert_equal 'Closed', worst[:category]
    assert_equal 4, worst[:index]
    assert_equal 1, worst[:points]
  end

  test "open and closed numeric alphabets no longer collide" do
    t = tabulator(open_scoring: '1', closed_scoring: '&')

    # "1" means first place in an open heat and a bottom score in a closed one.
    open = t.tabulate('1', 'Open')
    assert_equal 'Open', open[:category]
    assert_equal 5, open[:points]

    closed = t.tabulate('1', 'Closed')
    assert_equal 'Closed', closed[:category]
    assert_equal 1, closed[:points]
  end

  test "open scoring of number and feedback ranks five above one" do
    t = tabulator(open_scoring: '&', closed_scoring: 'G')

    assert_equal 5, t.tabulate('5', 'Open')[:points]
    assert_equal 1, t.tabulate('1', 'Open')[:points]
  end

  test "empty counts are sized to each bucket" do
    t = tabulator(open_scoring: '1', closed_scoring: '&')

    assert_equal({ 'Closed' => [0, 0, 0, 0, 0], 'Open' => [0, 0, 0, 0] }, t.empty_counts)
  end

  # ===== ORDINARY STYLES =====

  test "placements and letter grades are worth the same points" do
    t = tabulator(open_scoring: '1', closed_scoring: 'G')

    assert_equal [5, 3, 2, 1], %w(1 2 3 F).map { |v| t.tabulate(v, 'Open')[:points] }
    assert_equal [5, 3, 2, 1], %w(GH G S B).map { |v| t.tabulate(v, 'Closed')[:points] }
  end

  test "numeric scores count their face value and occupy no column" do
    t = tabulator(open_scoring: '#', closed_scoring: 'G')

    result = t.tabulate('85', 'Open')
    assert_nil result[:index]
    assert_equal 85, result[:points]
  end

  test "feedback only scoring puts nothing in the tables" do
    t = tabulator(open_scoring: '+', closed_scoring: 'G')

    assert_nil t.tabulate('F', 'Open')
  end

  # ===== EDGE CASES =====

  test "blank and unrecognized values are ignored" do
    t = tabulator(open_scoring: '1', closed_scoring: 'G')

    assert_nil t.tabulate(nil, 'Open')
    assert_nil t.tabulate('', 'Open')
    assert_nil t.tabulate('X', 'Open')
  end

  test "multi scores fall back to whichever alphabet recognizes them" do
    t = tabulator(open_scoring: '1', closed_scoring: 'G')

    # Multi heats score 1/2/3/F, which only the open bucket recognizes.
    multi = t.tabulate('2', 'Multi')
    assert_equal 'Open', multi[:category]
    assert_equal 3, multi[:points]
  end

  test "multi scores are dropped when no bucket recognizes them" do
    t = tabulator(open_scoring: '&', closed_scoring: '+')

    assert_nil t.tabulate('F', 'Multi')
  end

  test "solo scores never enter the tables" do
    # Solos are scored out of 100, a scale these tables cannot represent --
    # not even under numeric scoring, which would otherwise take any value.
    assert_nil tabulator(open_scoring: '1', closed_scoring: 'G').tabulate('92', 'Solo')
    assert_nil tabulator(open_scoring: '#', closed_scoring: '=').tabulate('92', 'Solo')
  end
end
