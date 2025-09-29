require "test_helper"

class DanceLimitsHelperTest < ActionView::TestCase
  include DanceLimitsHelper

  setup do
    @event = events(:one)
  end

  # ===== ROW CLASS TESTS =====

  test "limit_status_row_class returns red class when over limit" do
    result = limit_status_row_class(5, 3, 0)
    assert_equal "bg-red-50 hover:bg-red-100", result
  end

  test "limit_status_row_class returns yellow class when at limit" do
    result = limit_status_row_class(3, 3, 0)
    assert_equal "bg-yellow-50 hover:bg-yellow-100", result
  end

  test "limit_status_row_class returns white class for even index under limit" do
    result = limit_status_row_class(2, 3, 0)
    assert_equal "bg-white hover:bg-gray-50", result
  end

  test "limit_status_row_class returns gray class for odd index under limit" do
    result = limit_status_row_class(2, 3, 1)
    assert_equal "bg-gray-50 hover:bg-gray-100", result
  end

  # ===== TEXT CLASS TESTS =====

  test "limit_status_text_class returns red class when over limit" do
    result = limit_status_text_class(5, 3)
    assert_equal "text-red-600", result
  end

  test "limit_status_text_class returns orange class when at limit" do
    result = limit_status_text_class(3, 3)
    assert_equal "text-orange-600", result
  end

  test "limit_status_text_class returns gray class when under limit" do
    result = limit_status_text_class(2, 3)
    assert_equal "text-gray-900", result
  end

  # ===== PERCENTAGE TESTS =====

  test "limit_percentage calculates correct percentage" do
    assert_equal 50.0, limit_percentage(3, 6)
    assert_equal 100.0, limit_percentage(5, 5)
    assert_equal 150.0, limit_percentage(6, 4)
  end

  test "limit_percentage returns 0 for nil limit" do
    assert_equal 0, limit_percentage(5, nil)
  end

  test "limit_percentage returns 0 for zero limit" do
    assert_equal 0, limit_percentage(5, 0)
  end

  test "limit_percentage rounds to 1 decimal place" do
    assert_equal 33.3, limit_percentage(1, 3)
    assert_equal 66.7, limit_percentage(2, 3)
  end

  # ===== BADGE TESTS =====

  test "limit_status_badge returns OVER badge when over limit" do
    result = limit_status_badge(5, 3)
    assert_includes result, "OVER"
    assert_includes result, "bg-red-100 text-red-700"
  end

  test "limit_status_badge returns AT LIMIT badge when at limit" do
    result = limit_status_badge(3, 3)
    assert_includes result, "AT LIMIT"
    assert_includes result, "bg-orange-100 text-orange-700"
  end

  test "limit_status_badge returns nil when under limit" do
    result = limit_status_badge(2, 3)
    assert_nil result
  end

  test "limit_status_badge returns nil for nil inputs" do
    assert_nil limit_status_badge(nil, 3)
    assert_nil limit_status_badge(3, nil)
  end

  # ===== FORMATTING TESTS =====

  test "format_lead_follow_counts formats correctly" do
    result = format_lead_follow_counts(3, 2)
    assert_includes result, '3'
    assert_includes result, '2'
    assert_includes result, 'text-blue-600'
    assert_includes result, 'text-purple-600'
  end

  test "format_excess formats positive excess" do
    result = format_excess(3)
    assert_includes result, "+3"
    assert_includes result, "bg-red-100 text-red-700"
  end

  test "format_excess returns nil for zero or negative excess" do
    assert_nil format_excess(0)
    assert_nil format_excess(-1)
  end

  # ===== CATEGORY TESTS =====

  test "combined_categories? returns true when heat_range_cat is 1" do
    @event.update!(heat_range_cat: 1)
    assert combined_categories?
  end

  test "combined_categories? returns false when heat_range_cat is not 1" do
    @event.update!(heat_range_cat: 0)
    assert_not combined_categories?
  end

  test "effective_category_display returns Open/Closed when combined" do
    @event.update!(heat_range_cat: 1)
    assert_equal "Open/Closed", effective_category_display("Open")
    assert_equal "Open/Closed", effective_category_display("Closed")
  end

  test "effective_category_display returns original when not combined" do
    @event.update!(heat_range_cat: 0)
    assert_equal "Open", effective_category_display("Open")
    assert_equal "Closed", effective_category_display("Closed")
  end

  test "effective_category_display preserves non-Open/Closed categories" do
    @event.update!(heat_range_cat: 1)
    assert_equal "Multi", effective_category_display("Multi")
    assert_equal "Solo", effective_category_display("Solo")
  end

  # ===== SUMMARY STATS TESTS =====

  test "limit_summary_stats calculates correct counts" do
    people_data = [
      { total_count: 2 },
      { total_count: 5 },
      { total_count: 5 },
      { total_count: 7 }
    ]

    stats = limit_summary_stats(people_data, 5)

    assert_equal 4, stats[:total]
    assert_equal 2, stats[:at_limit]
    assert_equal 1, stats[:over_limit]
    assert_equal 1, stats[:under_limit]
  end

  test "limit_summary_stats handles empty array" do
    stats = limit_summary_stats([], 5)

    assert_equal 0, stats[:total]
    assert_equal 0, stats[:at_limit]
    assert_equal 0, stats[:over_limit]
    assert_equal 0, stats[:under_limit]
  end

  # ===== HTML SAFETY TESTS =====

  test "format_lead_follow_counts returns html_safe string" do
    result = format_lead_follow_counts(3, 2)
    assert result.html_safe?
  end

  test "limit_status_badge returns html_safe string when not nil" do
    result = limit_status_badge(5, 3)
    assert result.html_safe?
  end

  test "format_excess returns html_safe string when not nil" do
    result = format_excess(3)
    assert result.html_safe?
  end
end