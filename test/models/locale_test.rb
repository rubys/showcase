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
end