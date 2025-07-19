require "application_system_test_case"

class LocaleSystemTest < ApplicationSystemTestCase
  test "Locale provides consistent locale options" do
    # This is a simpler test that doesn't require authentication
    # It verifies that Locale is properly integrated
    
    # Test that all locale codes are valid
    Locale.all_codes.each do |code|
      assert_match /^[a-z]{2}_[A-Z]{2}$/, code, "Locale code #{code} should be in xx_XX format"
    end
    
    # Test that select options are properly formatted
    options = Locale.select_options
    assert_equal 12, options.count, "Should have 12 locale options"
    
    # Verify some key locales are present
    locale_names = options.map(&:first)
    assert_includes locale_names, "English (US)"
    assert_includes locale_names, "French (CA)"
    assert_includes locale_names, "Japanese (JP)"
    
    # Test the format conversion works
    assert_equal "en-US", Locale.to_browser_format("en_US")
    assert_equal "fr_CA", Locale.to_rails_format("fr-CA")
  end
  
  test "ApplicationHelper can format dates for all configured locales" do
    # Test that the helper can handle all locales without errors
    helper = ApplicationController.helpers
    test_date = "2024-12-25"
    
    Locale.all_codes.each do |locale|
      formatted = helper.localized_date(test_date, locale)
      assert formatted.present?, "Should format date for locale #{locale}"
      assert formatted.include?("2024"), "Formatted date should include year"
    end
  end
end