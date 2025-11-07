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

  test "localized_currency formats USD correctly" do
    @locale = "en_US"
    assert_equal "$1,234.56", localized_currency(1234.56)
    assert_equal "$0.00", localized_currency(0)
    assert_equal "-$100.50", localized_currency(-100.50)
  end

  test "localized_currency formats JPY correctly" do
    @locale = "ja_JP"
    assert_equal "¥1,235", localized_currency(1234.56)
    assert_equal "¥0", localized_currency(0)
    assert_equal "-¥101", localized_currency(-100.50)  # JPY rounds to nearest integer
  end

  test "localized_currency formats EUR correctly" do
    @locale = "fr_FR"
    assert_equal "1 234,56 €", localized_currency(1234.56)
    
    @locale = "de_DE"
    assert_equal "1.234,56 €", localized_currency(1234.56)
    
    @locale = "it_IT"
    assert_equal "€ 1 234,56", localized_currency(1234.56)
  end

  test "localized_currency formats GBP correctly" do
    @locale = "en_GB"
    assert_equal "£1,234.56", localized_currency(1234.56)
  end

  test "localized_currency handles nil" do
    assert_nil localized_currency(nil)
  end

  test "localized_currency respects explicit currency parameter" do
    @locale = "en_US"
    assert_equal "€1,234.56", localized_currency(1234.56, nil, "EUR")
    assert_equal "¥1,235", localized_currency(1234.56, nil, "JPY")
  end

  test "localized_currency uses locale to determine currency" do
    @locale = "ja_JP"
    # Should use JPY for Japanese locale
    assert_equal "¥1,235", localized_currency(1234.56)

    @locale = "en_GB"
    # Should use GBP for UK locale
    assert_equal "£1,234.56", localized_currency(1234.56)

    @locale = "fr_FR"
    # Should use EUR for French locale
    assert_equal "1 234,56 €", localized_currency(1234.56)
  end

  # ===== COUPLE_NAMES TESTS =====

  test "couple_names formats regular couple correctly" do
    lead = Person.new(id: 1, name: "John Doe")
    follow = Person.new(id: 2, name: "Jane Smith")
    entry = Entry.new(lead: lead, follow: follow)

    assert_equal "John Doe & Jane Smith", couple_names(entry)
  end

  test "couple_names formats solo with Nobody as follow" do
    lead = Person.new(id: 1, name: "John Doe")
    nobody = Person.new(id: 0, name: "Nobody")
    entry = Entry.new(lead: lead, follow: nobody)

    assert_equal "John Doe (Solo)", couple_names(entry)
  end

  test "couple_names formats solo with Nobody as lead" do
    nobody = Person.new(id: 0, name: "Nobody")
    follow = Person.new(id: 2, name: "Jane Smith")
    entry = Entry.new(lead: nobody, follow: follow)

    assert_equal "Jane Smith (Solo)", couple_names(entry)
  end

  test "couple_names formats formation with both Nobody" do
    nobody = Person.new(id: 0, name: "Nobody")
    entry = Entry.new(lead: nobody, follow: nobody)

    assert_equal "Nobody & Nobody", couple_names(entry)
  end

  test "couple_names works with Heat object" do
    lead = Person.new(id: 1, name: "John Doe")
    follow = Person.new(id: 2, name: "Jane Smith")
    entry = Entry.new(lead: lead, follow: follow)
    heat = Heat.new(entry: entry)

    assert_equal "John Doe & Jane Smith", couple_names(heat)
  end
end