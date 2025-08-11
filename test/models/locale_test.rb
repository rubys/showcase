require "test_helper"

class LocaleTest < ActiveSupport::TestCase
  test "all locales have required attributes" do
    Locale::SUPPORTED_LOCALES.each do |code, info|
      assert info[:name].present?, "Locale #{code} should have a display name"
      assert info[:browser].present?, "Locale #{code} should have a browser format"
      assert_match /^[a-z]{2}-[A-Z]{2}$/, info[:browser], "Browser format for #{code} should be xx-XX"
      assert_match /^[a-z]{2}_[A-Z]{2}$/, code, "Rails format should be xx_XX"
    end
  end

  test "select_options returns correct format" do
    options = Locale.select_options
    assert_kind_of Array, options
    assert options.all? { |opt| opt.is_a?(Array) && opt.size == 2 }
    
    # Check a few known options
    assert_includes options, ["English (US)", "en_US"]
    assert_includes options, ["French (CA)", "fr_CA"]
    assert_includes options, ["Japanese (JP)", "ja_JP"]
  end

  test "to_browser_format converts correctly" do
    assert_equal "en-US", Locale.to_browser_format("en_US")
    assert_equal "fr-CA", Locale.to_browser_format("fr_CA")
    assert_equal "ja-JP", Locale.to_browser_format("ja_JP")
    
    # Test fallback for unknown locale
    assert_equal "xx-YY", Locale.to_browser_format("xx_YY")
    
    # Test nil handling
    assert_nil Locale.to_browser_format(nil)
  end

  test "to_rails_format converts correctly" do
    assert_equal "en_US", Locale.to_rails_format("en-US")
    assert_equal "fr_CA", Locale.to_rails_format("fr-CA")
    assert_equal "ja_JP", Locale.to_rails_format("ja-JP")
    
    # Test fallback for unknown locale
    assert_equal "xx_YY", Locale.to_rails_format("xx-YY")
    
    # Test nil handling
    assert_nil Locale.to_rails_format(nil)
  end

  test "supported? identifies valid locales" do
    # Test Rails format
    assert Locale.supported?("en_US")
    assert Locale.supported?("fr_CA")
    
    # Test browser format
    assert Locale.supported?("en-US")
    assert Locale.supported?("fr-CA")
    
    # Test unsupported
    assert_not Locale.supported?("xx_YY")
    assert_not Locale.supported?("xx-YY")
    assert_not Locale.supported?(nil)
  end

  test "ApplicationHelper handles all Locale locales" do
    # This test ensures ApplicationHelper can format dates for all configured locales
    helper = ApplicationController.helpers
    test_date = "2024-03-15"
    
    Locale.all_codes.each do |locale_code|
      result = helper.localized_date(test_date, locale_code)
      assert result.present?, "ApplicationHelper should format date for locale #{locale_code}"
      assert_not_equal test_date, result, "Date should be formatted, not returned as-is for #{locale_code}"
    end
  end

  test "number_format handles decimal numbers" do
    # Test US format
    assert_equal "1,234.56", Locale.number_format(1234.56, "en-US")
    assert_equal "1,234,567.89", Locale.number_format(1234567.89, "en-US")
    
    # Test European formats with space thousands separator
    assert_equal "1 234,56", Locale.number_format(1234.56, "fr-FR")
    assert_equal "1 234,56", Locale.number_format(1234.56, "es-ES")
    
    # Test German format with dot thousands separator
    assert_equal "1.234,56", Locale.number_format(1234.56, "de-DE")
    
    # Test negative numbers
    assert_equal "-1,234.56", Locale.number_format(-1234.56, "en-US")
    assert_equal "-1 234,56", Locale.number_format(-1234.56, "fr-FR")
  end

  test "number_format handles currency" do
    # Test USD formatting
    assert_equal "$1,234.56", Locale.number_format(1234.56, "en-US", style: 'currency', currency: 'USD')
    assert_equal "$1,234,567.89", Locale.number_format(1234567.89, "en-US", style: 'currency', currency: 'USD')
    
    # Test EUR formatting
    assert_equal "1 234,56 €", Locale.number_format(1234.56, "fr-FR", style: 'currency', currency: 'EUR')
    assert_equal "1.234,56 €", Locale.number_format(1234.56, "de-DE", style: 'currency', currency: 'EUR')
    assert_equal "€ 1 234,56", Locale.number_format(1234.56, "it-IT", style: 'currency', currency: 'EUR')
    
    # Test GBP formatting
    assert_equal "£1,234.56", Locale.number_format(1234.56, "en-GB", style: 'currency', currency: 'GBP')
    
    # Test JPY formatting (no decimal places)
    assert_equal "¥1,235", Locale.number_format(1234.56, "ja-JP", style: 'currency', currency: 'JPY')
    assert_equal "¥1,234,568", Locale.number_format(1234567.89, "ja-JP", style: 'currency', currency: 'JPY')
    
    # Test negative currency
    assert_equal "-$1,234.56", Locale.number_format(-1234.56, "en-US", style: 'currency', currency: 'USD')
  end

  test "number_format handles percent" do
    assert_equal "12.35%", Locale.number_format(0.1234567, "en-US", style: 'percent')
    assert_equal "12,35%", Locale.number_format(0.1234567, "fr-FR", style: 'percent')
    assert_equal "12,35%", Locale.number_format(0.1234567, "de-DE", style: 'percent')
    
    # Test negative percents
    assert_equal "-12.35%", Locale.number_format(-0.1234567, "en-US", style: 'percent')
  end

  test "number_format handles fraction digit options" do
    # Test minimum fraction digits
    assert_equal "1,234.00", Locale.number_format(1234, "en-US", minimum_fraction_digits: 2)
    assert_equal "1,234.50", Locale.number_format(1234.5, "en-US", minimum_fraction_digits: 2)
    
    # Test maximum fraction digits
    assert_equal "1,234.57", Locale.number_format(1234.567, "en-US", maximum_fraction_digits: 2)
    assert_equal "1,235", Locale.number_format(1234.567, "en-US", maximum_fraction_digits: 0)
    
    # Test both min and max
    assert_equal "1,234.00", Locale.number_format(1234, "en-US", minimum_fraction_digits: 2, maximum_fraction_digits: 4)
    assert_equal "1,234.567", Locale.number_format(1234.567, "en-US", minimum_fraction_digits: 0, maximum_fraction_digits: 3)
  end

  test "number_format handles special cases" do
    # Test nil
    assert_nil Locale.number_format(nil, "en-US")
    
    # Test zero
    assert_equal "0.00", Locale.number_format(0, "en-US")
    assert_equal "$0.00", Locale.number_format(0, "en-US", style: 'currency')
    
    # Test very large numbers
    assert_equal "123,456,789.00", Locale.number_format(123456789, "en-US")
    assert_equal "123 456 789,00", Locale.number_format(123456789, "fr-FR")
    
    # Test very small numbers
    assert_equal "0.12", Locale.number_format(0.123456, "en-US", maximum_fraction_digits: 2)
  end

  test "number_format handles all supported locales" do
    test_number = 1234567.89
    
    Locale::SUPPORTED_LOCALES.each do |rails_code, info|
      browser_code = info[:browser]
      
      # Test decimal format
      result = Locale.number_format(test_number, browser_code)
      assert result.present?, "Should format decimal for #{browser_code}"
      
      # Test currency format
      result = Locale.number_format(test_number, browser_code, style: 'currency', currency: 'USD')
      assert result.present?, "Should format currency for #{browser_code}"
      assert result.include?('$'), "Should include currency symbol for #{browser_code}"
      
      # Test percent format
      result = Locale.number_format(0.5, browser_code, style: 'percent')
      assert result.present?, "Should format percent for #{browser_code}"
      assert result.include?('%'), "Should include percent sign for #{browser_code}"
    end
  end
end