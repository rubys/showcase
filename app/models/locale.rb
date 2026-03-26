# Centralized locale service providing configuration, formatting, and localization
# This ensures consistency across all locale-related functionality in the application,
# both in server-side rendering and client-side JavaScript which makes use of
# Intl.DateTimeFormat in the date-range stimulus controller.
class Locale
  ENGLISH_MONTHS = %w[January February March April May June July August September October November December].freeze
  ENGLISH_WEEKDAYS = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze

  CURRENCY_SYMBOLS = {
    'USD' => '$', 'EUR' => '€', 'GBP' => '£', 'JPY' => '¥',
    'CAD' => '$', 'AUD' => '$', 'PLN' => 'zł', 'UAH' => '₴', 'RON' => 'lei'
  }.freeze

  # All locale-specific data in one place. Adding a new locale = adding one hash entry.
  # Templates use Ruby named references: %{day}, %{month}, %{year}, %{weekday}
  # Range templates use: %{sd}/%{ed} (start/end day), %{sm}/%{em} (start/end month),
  #                      %{sy}/%{ey} (start/end year)
  SUPPORTED_LOCALES = {
    'en_US' => {
      name: 'English (US)', browser: 'en-US',
      months: ENGLISH_MONTHS, weekdays: ENGLISH_WEEKDAYS,
      date_fmt: '%{weekday}, %{month} %{day}, %{year}',
      range_same_month:      '%{sm} %{sd}–%{ed}',
      range_same_month_year: '%{sm} %{sd}–%{ed}, %{sy}',
      range_diff_month:      '%{sm} %{sd} – %{em} %{ed}',
      range_diff_month_year: '%{sm} %{sd} – %{em} %{ed}, %{sy}',
      range_diff_year:       '%{sm} %{sd}, %{sy} – %{em} %{ed}, %{ey}',
      time_fmt: '%-I:%M %P',
      thousand_sep: ',', decimal_sep: '.',
      currency_fmt: '%{symbol}%{amount}',
    },
    'en_GB' => {
      name: 'English (UK)', browser: 'en-GB',
      months: ENGLISH_MONTHS, weekdays: ENGLISH_WEEKDAYS,
      date_fmt: '%{weekday}, %{day} %{month} %{year}',
      range_same_month:      '%{sd}–%{ed} %{sm}',
      range_same_month_year: '%{sd}–%{ed} %{sm} %{sy}',
      range_diff_month:      '%{sd} %{sm} – %{ed} %{em}',
      range_diff_month_year: '%{sd} %{sm} – %{ed} %{em} %{sy}',
      range_diff_year:       '%{sd} %{sm} %{sy} – %{ed} %{em} %{ey}',
      time_fmt: '%-I:%M %P',
      thousand_sep: ',', decimal_sep: '.',
      currency_fmt: '%{symbol}%{amount}',
    },
    'en_CA' => {
      name: 'English (CA)', browser: 'en-CA',
      months: ENGLISH_MONTHS, weekdays: ENGLISH_WEEKDAYS,
      date_fmt: '%{weekday}, %{day} %{month} %{year}',
      range_same_month:      '%{sd}–%{ed} %{sm}',
      range_same_month_year: '%{sd}–%{ed} %{sm} %{sy}',
      range_diff_month:      '%{sd} %{sm} – %{ed} %{em}',
      range_diff_month_year: '%{sd} %{sm} – %{ed} %{em} %{sy}',
      range_diff_year:       '%{sd} %{sm} %{sy} – %{ed} %{em} %{ey}',
      time_fmt: '%-I:%M %P',
      thousand_sep: ',', decimal_sep: '.',
      currency_fmt: '%{symbol}%{amount}',
    },
    'en_AU' => {
      name: 'English (AU)', browser: 'en-AU',
      months: ENGLISH_MONTHS, weekdays: ENGLISH_WEEKDAYS,
      date_fmt: '%{weekday}, %{day} %{month} %{year}',
      range_same_month:      '%{sd}–%{ed} %{sm}',
      range_same_month_year: '%{sd}–%{ed} %{sm} %{sy}',
      range_diff_month:      '%{sd} %{sm} – %{ed} %{em}',
      range_diff_month_year: '%{sd} %{sm} – %{ed} %{em} %{sy}',
      range_diff_year:       '%{sd} %{sm} %{sy} – %{ed} %{em} %{ey}',
      time_fmt: '%-I:%M %P',
      thousand_sep: ',', decimal_sep: '.',
      currency_fmt: '%{symbol}%{amount}',
    },
    'fr_CA' => {
      name: 'French (CA)', browser: 'fr-CA',
      months: %w[janvier février mars avril mai juin juillet août septembre octobre novembre décembre],
      weekdays: %w[dimanche lundi mardi mercredi jeudi vendredi samedi],
      date_fmt: '%{weekday} %{day} %{month} %{year}',
      range_same_month:      '%{sd} au %{ed} %{sm}',
      range_same_month_year: '%{sd} au %{ed} %{sm} %{sy}',
      range_diff_month:      '%{sd} %{sm} au %{ed} %{em}',
      range_diff_month_year: '%{sd} %{sm} au %{ed} %{em} %{sy}',
      range_diff_year:       '%{sd} %{sm} %{sy} au %{ed} %{em} %{ey}',
      time_fmt: '%-I:%M %P',
      thousand_sep: ' ', decimal_sep: ',',
      currency_fmt: '%{amount} %{symbol}',
    },
    'fr_FR' => {
      name: 'French (FR)', browser: 'fr-FR',
      months: %w[janvier février mars avril mai juin juillet août septembre octobre novembre décembre],
      weekdays: %w[dimanche lundi mardi mercredi jeudi vendredi samedi],
      date_fmt: '%{weekday} %{day} %{month} %{year}',
      range_same_month:      '%{sd} au %{ed} %{sm}',
      range_same_month_year: '%{sd} au %{ed} %{sm} %{sy}',
      range_diff_month:      '%{sd} %{sm} au %{ed} %{em}',
      range_diff_month_year: '%{sd} %{sm} au %{ed} %{em} %{sy}',
      range_diff_year:       '%{sd} %{sm} %{sy} au %{ed} %{em} %{ey}',
      time_fmt: '%H:%M',
      thousand_sep: ' ', decimal_sep: ',',
      currency_fmt: '%{amount} %{symbol}',
    },
    'pl_PL' => {
      name: 'Polish (PL)', browser: 'pl-PL',
      months: %w[stycznia lutego marca kwietnia maja czerwca lipca sierpnia września października listopada grudnia],
      weekdays: %w[niedziela poniedziałek wtorek środa czwartek piątek sobota],
      date_fmt: '%{weekday}, %{day} %{month} %{year}',
      range_same_month:      '%{sm} %{sd}–%{ed}',
      range_same_month_year: '%{sm} %{sd}–%{ed}, %{sy}',
      range_diff_month:      '%{sm} %{sd} – %{em} %{ed}',
      range_diff_month_year: '%{sm} %{sd} – %{em} %{ed}, %{sy}',
      range_diff_year:       '%{sm} %{sd}, %{sy} – %{em} %{ed}, %{ey}',
      time_fmt: '%H:%M',
      thousand_sep: ' ', decimal_sep: ',',
      currency_fmt: '%{amount} %{symbol}',
    },
    'de_DE' => {
      name: 'German (DE)', browser: 'de-DE',
      months: %w[Januar Februar März April Mai Juni Juli August September Oktober November Dezember],
      weekdays: %w[Sonntag Montag Dienstag Mittwoch Donnerstag Freitag Samstag],
      date_fmt: '%{weekday}, %{day}. %{month} %{year}',
      range_same_month:      '%{sd}.–%{ed}. %{sm}',
      range_same_month_year: '%{sd}.–%{ed}. %{sm} %{sy}',
      range_diff_month:      '%{sd}. %{sm} – %{ed}. %{em}',
      range_diff_month_year: '%{sd}. %{sm} – %{ed}. %{em} %{sy}',
      range_diff_year:       '%{sd}. %{sm} %{sy} – %{ed}. %{em} %{ey}',
      time_fmt: '%H:%M',
      thousand_sep: '.', decimal_sep: ',',
      currency_fmt: '%{amount} %{symbol}',
    },
    'es_ES' => {
      name: 'Spanish (ES)', browser: 'es-ES',
      months: %w[enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre],
      weekdays: %w[domingo lunes martes miércoles jueves viernes sábado],
      date_fmt: '%{weekday}, %{day} de %{month} de %{year}',
      range_same_month:      '%{sm} %{sd}–%{ed}',
      range_same_month_year: '%{sm} %{sd}–%{ed}, %{sy}',
      range_diff_month:      '%{sm} %{sd} – %{em} %{ed}',
      range_diff_month_year: '%{sm} %{sd} – %{em} %{ed}, %{sy}',
      range_diff_year:       '%{sm} %{sd}, %{sy} – %{em} %{ed}, %{ey}',
      time_fmt: '%H:%M',
      thousand_sep: ' ', decimal_sep: ',',
      currency_fmt: '%{amount} %{symbol}',
    },
    'it_IT' => {
      name: 'Italian (IT)', browser: 'it-IT',
      months: %w[gennaio febbraio marzo aprile maggio giugno luglio agosto settembre ottobre novembre dicembre],
      weekdays: %w[domenica lunedì martedì mercoledì giovedì venerdì sabato],
      date_fmt: '%{weekday} %{day} %{month} %{year}',
      range_same_month:      '%{sm} %{sd}–%{ed}',
      range_same_month_year: '%{sm} %{sd}–%{ed}, %{sy}',
      range_diff_month:      '%{sm} %{sd} – %{em} %{ed}',
      range_diff_month_year: '%{sm} %{sd} – %{em} %{ed}, %{sy}',
      range_diff_year:       '%{sm} %{sd}, %{sy} – %{em} %{ed}, %{ey}',
      time_fmt: '%H:%M',
      thousand_sep: ' ', decimal_sep: ',',
      currency_fmt: '%{symbol} %{amount}',
    },
    'uk_UA' => {
      name: 'Ukrainian (UA)', browser: 'uk-UA',
      months: %w[січня лютого березня квітня травня червня липня серпня вересня жовтня листопада грудня],
      weekdays: ['неділя', 'понеділок', 'вівторок', 'середа', 'четвер', "п'ятниця", 'субота'],
      date_fmt: '%{weekday}, %{day} %{month} %{year}',
      range_same_month:      '%{sm} %{sd}–%{ed}',
      range_same_month_year: '%{sm} %{sd}–%{ed}, %{sy}',
      range_diff_month:      '%{sm} %{sd} – %{em} %{ed}',
      range_diff_month_year: '%{sm} %{sd} – %{em} %{ed}, %{sy}',
      range_diff_year:       '%{sm} %{sd}, %{sy} – %{em} %{ed}, %{ey}',
      time_fmt: '%H:%M',
      thousand_sep: ' ', decimal_sep: ',',
      currency_fmt: '%{amount} %{symbol}',
    },
    'ro_RO' => {
      name: 'Romanian (RO)', browser: 'ro-RO',
      months: %w[ianuarie februarie martie aprilie mai iunie iulie august septembrie octombrie noiembrie decembrie],
      weekdays: %w[duminică luni marți miercuri joi vineri sâmbătă],
      date_fmt: '%{weekday}, %{day} %{month} %{year}',
      range_same_month:      '%{sd}–%{ed} %{sm}',
      range_same_month_year: '%{sd}–%{ed} %{sm} %{sy}',
      range_diff_month:      '%{sd} %{sm} – %{ed} %{em}',
      range_diff_month_year: '%{sd} %{sm} – %{ed} %{em} %{sy}',
      range_diff_year:       '%{sd} %{sm} %{sy} – %{ed} %{em} %{ey}',
      time_fmt: '%H:%M',
      thousand_sep: ' ', decimal_sep: ',',
      currency_fmt: '%{amount} %{symbol}',
    },
    'ja_JP' => {
      name: 'Japanese (JP)', browser: 'ja-JP',
      months: %w[1 2 3 4 5 6 7 8 9 10 11 12],
      weekdays: %w[日 月 火 水 木 金 土],
      date_fmt: '%{year}年%{month}月%{day}日(%{weekday})',
      range_same_month:      '%{sy}年%{sm}月%{sd}日〜%{em}月%{ed}日',
      range_same_month_year: '%{sy}年%{sm}月%{sd}日〜%{em}月%{ed}日',
      range_diff_month:      '%{sy}年%{sm}月%{sd}日〜%{em}月%{ed}日',
      range_diff_month_year: '%{sy}年%{sm}月%{sd}日〜%{em}月%{ed}日',
      range_diff_year:       '%{sy}年%{sm}月%{sd}日〜%{ey}年%{em}月%{ed}日',
      time_fmt: '%H:%M',
      thousand_sep: ',', decimal_sep: '.',
      currency_fmt: '%{symbol}%{amount}',
    },
  }.freeze

  # Reverse lookup: browser format → locale data
  BY_BROWSER = SUPPORTED_LOCALES.each_with_object({}) { |(_, v), h| h[v[:browser]] = v }.freeze

  DEFAULT_DATA = BY_BROWSER['en-US']

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

  # Get localized month names for a locale (browser format)
  def self.month_names(locale)
    data = BY_BROWSER[locale] || DEFAULT_DATA
    data[:months]
  end

  # Get localized weekday names for a locale (Sunday = 0, browser format)
  def self.weekday_names(locale)
    data = BY_BROWSER[locale] || DEFAULT_DATA
    data[:weekdays]
  end

  # Format a single date according to locale conventions (browser format)
  def self.format_single_date(date, locale)
    data = BY_BROWSER[locale] || DEFAULT_DATA
    data[:date_fmt] % {
      weekday: data[:weekdays][date.wday],
      month: data[:months][date.month - 1],
      day: date.day,
      year: date.year
    }
  end

  # Format a date range according to locale conventions (browser format)
  def self.format_date_range(start_date, end_date, locale)
    data = BY_BROWSER[locale] || DEFAULT_DATA
    show_year = start_date.year != Date.current.year

    vars = {
      sd: start_date.day, ed: end_date.day,
      sm: data[:months][start_date.month - 1],
      em: data[:months][end_date.month - 1],
      sy: start_date.year, ey: end_date.year
    }

    template = if start_date.year != end_date.year
      data[:range_diff_year]
    elsif start_date.month == end_date.month
      show_year ? data[:range_same_month_year] : data[:range_same_month]
    else
      show_year ? data[:range_diff_month_year] : data[:range_diff_month]
    end

    template % vars
  end

  # Format time according to locale conventions (browser format)
  def self.format_time(time, locale)
    return nil unless time
    data = BY_BROWSER[locale] || DEFAULT_DATA
    time.strftime(data[:time_fmt])
  end

  # Format a number according to locale conventions with optional currency
  # Options:
  #   :style - 'decimal' (default), 'currency', 'percent'
  #   :currency - Currency code (e.g., 'USD', 'EUR', 'JPY')
  #   :minimum_fraction_digits - Minimum number of fraction digits
  #   :maximum_fraction_digits - Maximum number of fraction digits
  def self.number_format(number, locale, options = {})
    return nil unless number

    data = BY_BROWSER[locale] || DEFAULT_DATA
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
    formatted_number = max_fraction == 0 ? number.round.to_i : number.round(max_fraction)

    if style == 'percent'
      percent_value = number * 100
      parts = format_number_parts(percent_value, data, min_fraction, max_fraction)
      (number < 0 ? '-' : '') + parts + '%'
    elsif style == 'currency'
      parts = format_number_parts(formatted_number, data, min_fraction, max_fraction)
      symbol = CURRENCY_SYMBOLS[currency] || currency
      formatted = data[:currency_fmt] % { symbol: symbol, amount: parts }
      formatted_number < 0 ? "-#{formatted}" : formatted
    else
      parts = format_number_parts(formatted_number, data, min_fraction, max_fraction)
      (formatted_number < 0 ? '-' : '') + parts
    end
  end

  private

  # Format the number parts with locale-appropriate separators
  def self.format_number_parts(number, data, min_fraction, max_fraction)
    thousand_sep = data[:thousand_sep]
    decimal_sep = data[:decimal_sep]

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
      decimal_part = decimal_part.ljust(min_fraction, '0')[0, max_fraction]
      decimal_part = decimal_part.sub(/0+$/, '') if min_fraction == 0
      decimal_part.empty? ? integer_part : "#{integer_part}#{decimal_sep}#{decimal_part}"
    else
      integer_part
    end
  end
end
