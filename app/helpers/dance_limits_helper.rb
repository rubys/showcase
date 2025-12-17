module DanceLimitsHelper
  # Determine the CSS class for a row based on limit status
  def limit_status_row_class(count, limit, index = 0)
    if limit && count > limit
      "bg-red-50 hover:bg-red-100"
    elsif limit && count == limit
      "bg-yellow-50 hover:bg-yellow-100"
    elsif index.even?
      "bg-white hover:bg-gray-50"
    else
      "bg-gray-50 hover:bg-gray-100"
    end
  end

  # Determine the text color class based on limit status
  def limit_status_text_class(count, limit)
    if limit && count > limit
      "text-red-600"
    elsif limit && count == limit
      "text-orange-600"
    else
      "text-gray-900"
    end
  end

  # Calculate percentage of limit used
  def limit_percentage(count, limit)
    return 0 if limit.nil? || limit == 0
    ((count.to_f / limit) * 100).round(1)
  end

  # Generate a status badge for limit status
  def limit_status_badge(count, limit)
    return nil unless count && limit

    if count > limit
      content_tag(:span, "OVER", class: "ml-2 px-2 py-1 bg-red-100 text-red-700 rounded text-xs")
    elsif count == limit
      content_tag(:span, "AT LIMIT", class: "ml-2 px-2 py-1 bg-orange-100 text-orange-700 rounded text-xs")
    else
      nil
    end
  end

  # Format the lead/follow count display
  def format_lead_follow_counts(lead_count, follow_count)
    content_tag(:span) do
      concat(content_tag(:span, lead_count.to_s, class: "text-blue-600"))
      concat(" / ")
      concat(content_tag(:span, follow_count.to_s, class: "text-purple-600"))
    end
  end

  # Check if categories are combined for the current event
  def combined_categories?
    Event.current.heat_range_cat == 1
  end

  # Get display name for category based on event settings
  def effective_category_display(category)
    if combined_categories? && %w[Open Closed].include?(category)
      "Open/Closed"
    else
      category
    end
  end

  # Format excess count display
  def format_excess(excess)
    return nil if excess <= 0
    content_tag(:span, "+#{excess}", class: "px-2 py-1 bg-red-100 text-red-700 rounded font-medium")
  end

  # Summary statistics for limit status
  def limit_summary_stats(people_data, limit)
    {
      total: people_data.count,
      at_limit: limit ? people_data.count { |item| item[:total_count] == limit } : 0,
      over_limit: limit ? people_data.count { |item| item[:total_count] > limit } : 0,
      under_limit: limit ? people_data.count { |item| item[:total_count] < limit } : people_data.count
    }
  end
end