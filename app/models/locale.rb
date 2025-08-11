# Centralized locale service providing configuration, formatting, and localization
# This ensures consistency across all locale-related functionality in the application,
# both in server-side rendering and client-side JavaScript which makes use of
# Intl.DateTimeFormat in the date-range stimulus controller.
class Locale
  # Define all supported locales with their display names
  # Rails format uses underscores (en_US), browser format uses dashes (en-US)
  SUPPORTED_LOCALES = {
    'en_US' => { name: 'English (US)', browser: 'en-US' },
    'en_GB' => { name: 'English (UK)', browser: 'en-GB' },
    'en_CA' => { name: 'English (CA)', browser: 'en-CA' },
    'en_AU' => { name: 'English (AU)', browser: 'en-AU' },
    'fr_CA' => { name: 'French (CA)', browser: 'fr-CA' },
    'fr_FR' => { name: 'French (FR)', browser: 'fr-FR' },
    'pl_PL' => { name: 'Polish (PL)', browser: 'pl-PL' },
    'de_DE' => { name: 'German (DE)', browser: 'de-DE' },
    'es_ES' => { name: 'Spanish (ES)', browser: 'es-ES' },
    'it_IT' => { name: 'Italian (IT)', browser: 'it-IT' },
    'uk_UA' => { name: 'Ukrainian (UA)', browser: 'uk-UA' },
    'ja_JP' => { name: 'Japanese (JP)', browser: 'ja-JP' }
  }.freeze

  # Get options for select dropdown [[display_name, value], ...]
  def self.select_options
    SUPPORTED_LOCALES.map { |code, info| [info[:name], code] }
  end

  # Convert Rails format (underscore) to browser format (dash)
  def self.to_browser_format(rails_locale)
    return nil unless rails_locale
    info = SUPPORTED_LOCALES[rails_locale]
    info ? info[:browser] : rails_locale.gsub('_', '-')
  end

  # Convert browser format (dash) to Rails format (underscore)
  def self.to_rails_format(browser_locale)
    return nil unless browser_locale
    # Try to find by browser format
    match = SUPPORTED_LOCALES.find { |_code, info| info[:browser] == browser_locale }
    match ? match[0] : browser_locale.gsub('-', '_')
  end

  # Check if a locale is supported (accepts both formats)
  def self.supported?(locale)
    return false unless locale
    rails_format = locale.gsub('-', '_')
    SUPPORTED_LOCALES.key?(rails_format)
  end

  # Get all locale codes in Rails format
  def self.all_codes
    SUPPORTED_LOCALES.keys
  end

  # Get locale display name
  def self.display_name(locale)
    rails_format = locale.gsub('-', '_')
    SUPPORTED_LOCALES.dig(rails_format, :name)
  end

  # Get localized month names for a locale
  # Note: expects browser format (dash) as used by ApplicationHelper
  def self.month_names(locale)
    case locale
    when 'fr-CA', 'fr-FR'
      ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre']
    when 'de-DE'
      ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember']
    when 'es-ES'
      ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre']
    when 'it-IT'
      ['gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno', 'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre']
    when 'pl-PL'
      ['stycznia', 'lutego', 'marca', 'kwietnia', 'maja', 'czerwca', 'lipca', 'sierpnia', 'września', 'października', 'listopada', 'grudnia']
    when 'uk-UA'
      ['січня', 'лютого', 'березня', 'квітня', 'травня', 'червня', 'липня', 'серпня', 'вересня', 'жовтня', 'листопада', 'грудня']
    when 'ja-JP'
      ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12']
    else # English (en-US, en-GB, en-CA, en-AU)
      ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']
    end
  end

  # Get localized weekday names for a locale (Sunday = 0)
  # Note: expects browser format (dash) as used by ApplicationHelper
  def self.weekday_names(locale)
    case locale
    when 'fr-CA', 'fr-FR'
      ['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi']
    when 'de-DE'
      ['Sonntag', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag']
    when 'es-ES'
      ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado']
    when 'it-IT'
      ['domenica', 'lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato']
    when 'pl-PL'
      ['niedziela', 'poniedziałek', 'wtorek', 'środa', 'czwartek', 'piątek', 'sobota']
    when 'uk-UA'
      ['неділя', 'понеділок', 'вівторок', 'середа', 'четвер', "п'ятниця", 'субота']
    when 'ja-JP'
      ['日', '月', '火', '水', '木', '金', '土']
    else # English (en-US, en-GB, en-CA, en-AU)
      ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
    end
  end

  # Format a single date according to locale conventions
  # Note: expects browser format (dash) as used by ApplicationHelper
  def self.format_single_date(date, locale)
    # Get locale-specific month and weekday names
    month_names = self.month_names(locale)
    weekday_names = self.weekday_names(locale)
    
    weekday = weekday_names[date.wday]
    month = month_names[date.month - 1]
    
    # Format based on locale conventions
    # Note: Locale service already converted to browser format (with dashes)
    case locale
    when 'en-GB', 'en-AU'
      "#{weekday}, #{date.day} #{month} #{date.year}"
    when 'en-CA'
      # Canadian English uses a format similar to UK
      "#{weekday}, #{date.day} #{month} #{date.year}"
    when 'fr-CA', 'fr-FR'
      "#{weekday} #{date.day} #{month} #{date.year}"
    when 'de-DE'
      "#{weekday}, #{date.day}. #{month} #{date.year}"
    when 'es-ES'
      "#{weekday}, #{date.day} de #{month} de #{date.year}"
    when 'it-IT'
      "#{weekday} #{date.day} #{month} #{date.year}"
    when 'pl-PL'
      "#{weekday}, #{date.day} #{month} #{date.year}"
    when 'uk-UA'
      "#{weekday}, #{date.day} #{month} #{date.year}"
    when 'ja-JP'
      "#{date.year}年#{date.month}月#{date.day}日(#{weekday})"
    else # Default to en-US format
      "#{weekday}, #{month} #{date.day}, #{date.year}"
    end
  end

  # Format a date range according to locale conventions
  # Note: expects browser format (dash) as used by ApplicationHelper
  def self.format_date_range(start_date, end_date, locale)
    year = Date.current.year
    show_year = start_date.year != year
    
    month_names = self.month_names(locale)
    start_month = month_names[start_date.month - 1]
    end_month = month_names[end_date.month - 1]
    
    # Format based on locale conventions
    # Note: Locale service already converted to browser format (with dashes)
    case locale
    when 'en-GB', 'en-AU', 'en-CA'
      if start_date.month == end_date.month && start_date.year == end_date.year
        if show_year
          "#{start_date.day}–#{end_date.day} #{start_month} #{start_date.year}"
        else
          "#{start_date.day}–#{end_date.day} #{start_month}"
        end
      elsif start_date.year == end_date.year
        if show_year
          "#{start_date.day} #{start_month} – #{end_date.day} #{end_month} #{start_date.year}"
        else
          "#{start_date.day} #{start_month} – #{end_date.day} #{end_month}"
        end
      else
        "#{start_date.day} #{start_month} #{start_date.year} – #{end_date.day} #{end_month} #{end_date.year}"
      end
    when 'fr-CA', 'fr-FR'
      if start_date.month == end_date.month && start_date.year == end_date.year
        if show_year
          "#{start_date.day} au #{end_date.day} #{start_month} #{start_date.year}"
        else
          "#{start_date.day} au #{end_date.day} #{start_month}"
        end
      elsif start_date.year == end_date.year
        if show_year
          "#{start_date.day} #{start_month} au #{end_date.day} #{end_month} #{start_date.year}"
        else
          "#{start_date.day} #{start_month} au #{end_date.day} #{end_month}"
        end
      else
        "#{start_date.day} #{start_month} #{start_date.year} au #{end_date.day} #{end_month} #{end_date.year}"
      end
    when 'de-DE'
      if start_date.month == end_date.month && start_date.year == end_date.year
        if show_year
          "#{start_date.day}.–#{end_date.day}. #{start_month} #{start_date.year}"
        else
          "#{start_date.day}.–#{end_date.day}. #{start_month}"
        end
      elsif start_date.year == end_date.year
        if show_year
          "#{start_date.day}. #{start_month} – #{end_date.day}. #{end_month} #{start_date.year}"
        else
          "#{start_date.day}. #{start_month} – #{end_date.day}. #{end_month}"
        end
      else
        "#{start_date.day}. #{start_month} #{start_date.year} – #{end_date.day}. #{end_month} #{end_date.year}"
      end
    when 'ja-JP'
      if start_date.year == end_date.year
        "#{start_date.year}年#{start_date.month}月#{start_date.day}日〜#{end_date.month}月#{end_date.day}日"
      else
        "#{start_date.year}年#{start_date.month}月#{start_date.day}日〜#{end_date.year}年#{end_date.month}月#{end_date.day}日"
      end
    else # Default to en-US format
      if start_date.month == end_date.month && start_date.year == end_date.year
        if show_year
          "#{start_month} #{start_date.day}–#{end_date.day}, #{start_date.year}"
        else
          "#{start_month} #{start_date.day}–#{end_date.day}"
        end
      elsif start_date.year == end_date.year
        if show_year
          "#{start_month} #{start_date.day} – #{end_month} #{end_date.day}, #{start_date.year}"
        else
          "#{start_month} #{start_date.day} – #{end_month} #{end_date.day}"
        end
      else
        "#{start_month} #{start_date.day}, #{start_date.year} – #{end_month} #{end_date.day}, #{end_date.year}"
      end
    end
  end

  # Format time according to locale conventions
  # Note: expects browser format (dash) as used by ApplicationHelper
  def self.format_time(time, locale)
    return nil unless time
    
    case locale
    when 'en-US', 'en-CA', 'en-GB', 'en-AU'
      time.strftime("%-I:%M %P")  # 12-hour format for English locales
    when 'fr-CA'
      time.strftime("%-I:%M %P")  # French Canada uses 12-hour format
    else # 24-hour format for most other locales
      time.strftime("%H:%M")  # 24-hour format for de-DE, fr-FR, es-ES, it-IT, pl-PL, uk-UA, ja-JP
    end
  end

  # Format a number according to locale conventions with optional currency
  # Options:
  #   :style - 'decimal' (default), 'currency', 'percent'
  #   :currency - Currency code (e.g., 'USD', 'EUR', 'JPY')
  #   :minimum_fraction_digits - Minimum number of fraction digits (default: 0 for JPY, 2 for others)
  #   :maximum_fraction_digits - Maximum number of fraction digits (default: 0 for JPY, 2 for others)
  # Note: expects browser format (dash) as used by ApplicationHelper
  def self.number_format(number, locale, options = {})
    return nil unless number
    
    style = options[:style] || 'decimal'
    currency = options[:currency] || 'USD'
    
    # Set default fraction digits based on currency
    if style == 'currency' && currency == 'JPY'
      min_fraction = options[:minimum_fraction_digits] || 0
      max_fraction = options[:maximum_fraction_digits] || 0
    else
      min_fraction = options[:minimum_fraction_digits] || 2
      max_fraction = options[:maximum_fraction_digits] || 2
    end
    
    # Round the number to the specified decimal places
    if max_fraction == 0
      formatted_number = number.round.to_i
    else
      formatted_number = number.round(max_fraction)
    end
    
    # Get the appropriate separators for the locale
    thousand_sep, decimal_sep = get_number_separators(locale)
    
    # Format the number with proper separators
    if style == 'percent'
      percent_value = number * 100  # Use original number, not rounded
      parts = format_number_parts(percent_value, thousand_sep, decimal_sep, min_fraction, max_fraction)
      formatted = (number < 0 ? '-' : '') + parts + '%'
    elsif style == 'currency'
      parts = format_number_parts(formatted_number, thousand_sep, decimal_sep, min_fraction, max_fraction)
      formatted = format_currency(parts, currency, locale, number < 0)
    else # decimal
      parts = format_number_parts(formatted_number, thousand_sep, decimal_sep, min_fraction, max_fraction)
      formatted = (number < 0 ? '-' : '') + parts
    end
    
    formatted
  end
  
  private
  
  # Get thousand and decimal separators for a locale
  def self.get_number_separators(locale)
    case locale
    when 'en-US', 'en-CA', 'ja-JP'
      [',', '.']  # 1,234.56
    when 'en-GB', 'en-AU'
      [',', '.']  # 1,234.56
    when 'fr-FR', 'es-ES', 'it-IT', 'pl-PL', 'uk-UA'
      [' ', ',']  # 1 234,56 (space for thousands)
    when 'fr-CA'
      [' ', ',']  # 1 234,56 (French Canada follows French conventions)
    when 'de-DE'
      ['.', ',']  # 1.234,56
    else
      [',', '.']  # Default to US format
    end
  end
  
  # Format the number parts with separators
  def self.format_number_parts(number, thousand_sep, decimal_sep, min_fraction, max_fraction)
    # Remember if the number is negative
    is_negative = number < 0
    
    # Split into integer and decimal parts
    if number.is_a?(Integer) || max_fraction == 0
      integer_part = number.to_i.abs.to_s
      decimal_part = ''
    else
      parts = ("%.#{max_fraction}f" % number.abs).split('.')
      integer_part = parts[0]
      decimal_part = parts[1] || ''
    end
    
    # Add thousand separators
    integer_part = integer_part.reverse.gsub(/(\d{3})(?=\d)/, "\\1#{thousand_sep}").reverse
    
    # Handle decimal part
    if min_fraction > 0 || (decimal_part != '' && decimal_part.to_i > 0)
      # Pad or trim decimal part
      decimal_part = decimal_part.ljust(min_fraction, '0')
      decimal_part = decimal_part[0, max_fraction]
      # Remove trailing zeros if not required by min_fraction
      if min_fraction == 0
        decimal_part = decimal_part.sub(/0+$/, '')
      end
      result = decimal_part.empty? ? integer_part : "#{integer_part}#{decimal_sep}#{decimal_part}"
    else
      result = integer_part
    end
    
    # Return the formatted string (without negative sign - that's handled in format_currency)
    result
  end
  
  # Format currency based on locale and currency code
  def self.format_currency(amount_str, currency, locale, is_negative = false)
    symbol = get_currency_symbol(currency, locale)
    
    formatted = case locale
    when 'en-US', 'en-CA'
      "#{symbol}#{amount_str}"  # $1,234.56
    when 'en-GB'
      if currency == 'GBP'
        "£#{amount_str}"  # £1,234.56
      else
        "#{symbol}#{amount_str}"
      end
    when 'en-AU'
      if currency == 'AUD'
        "$#{amount_str}"  # $1,234.56
      else
        "#{symbol}#{amount_str}"
      end
    when 'fr-FR', 'fr-CA'
      "#{amount_str} #{symbol}"  # 1 234,56 €
    when 'de-DE'
      "#{amount_str} #{symbol}"  # 1.234,56 €
    when 'es-ES'
      "#{amount_str} #{symbol}"  # 1 234,56 €
    when 'it-IT'
      "#{symbol} #{amount_str}"  # € 1 234,56
    when 'pl-PL'
      "#{amount_str} #{symbol}"  # 1 234,56 zł
    when 'uk-UA'
      "#{amount_str} #{symbol}"  # 1 234,56 ₴
    when 'ja-JP'
      if currency == 'JPY'
        "#{symbol}#{amount_str}"  # ¥1,234
      else
        "#{symbol}#{amount_str}"
      end
    else
      "#{symbol}#{amount_str}"  # Default format
    end
    
    # Add negative sign if needed
    is_negative ? "-#{formatted}" : formatted
  end
  
  # Get currency symbol for a currency code
  def self.get_currency_symbol(currency, locale)
    case currency
    when 'USD'
      '$'
    when 'EUR'
      '€'
    when 'GBP'
      '£'
    when 'JPY'
      '¥'
    when 'CAD'
      locale.start_with?('fr') ? '$' : '$'
    when 'AUD'
      '$'
    when 'PLN'
      'zł'
    when 'UAH'
      '₴'
    else
      currency  # Fall back to currency code
    end
  end
end