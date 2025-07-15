require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "localized_date formats single date correctly for different locales" do
    # Test US format
    assert_equal "Friday, March 15, 2024", localized_date("2024-03-15", "en-US")
    
    # Test UK format
    assert_equal "Friday, 15 March 2024", localized_date("2024-03-15", "en-GB")
    
    # Test French format
    assert_equal "vendredi 15 mars 2024", localized_date("2024-03-15", "fr-FR")
    
    # Test German format
    assert_equal "Freitag, 15. März 2024", localized_date("2024-03-15", "de-DE")
    
    # Test Japanese format
    assert_equal "2024年3月15日(金)", localized_date("2024-03-15", "ja-JP")
  end
  
  test "localized_date formats date ranges correctly for different locales" do
    # Test US format - same month
    assert_equal "March 15–17", localized_date("2025-03-15 - 2025-03-17", "en-US")
    
    # Test UK format - different months
    assert_equal "15 March – 17 April", localized_date("2025-03-15 - 2025-04-17", "en-GB")
    
    # Test French format - same month
    assert_equal "15 au 17 mars", localized_date("2025-03-15 - 2025-03-17", "fr-FR")
    
    # Test German format - different months
    assert_equal "15. März – 17. April", localized_date("2025-03-15 - 2025-04-17", "de-DE")
    
    # Test Japanese format
    assert_equal "2025年3月15日〜3月17日", localized_date("2025-03-15 - 2025-03-17", "ja-JP")
  end
  
  test "localized_date shows year when date is not current year" do
    # Test with a past year
    assert_equal "March 15–17, 2023", localized_date("2023-03-15 - 2023-03-17", "en-US")
    assert_equal "15 au 17 mars 2023", localized_date("2023-03-15 - 2023-03-17", "fr-FR")
  end
  
  test "localized_date handles invalid input gracefully" do
    # Should return original string for invalid date
    assert_equal "invalid-date", localized_date("invalid-date", "en-US")
    
    # Should handle nil
    assert_nil localized_date(nil, "en-US")
    
    # Should handle empty string
    assert_equal "", localized_date("", "en-US")
  end
  
  test "localized_date uses default locale when none provided" do
    # Should use en_US as default
    assert_equal "Friday, March 15, 2024", localized_date("2024-03-15")
  end
end