module ApplicationHelper
  def up_link(name, path_options, html_options = {}, &block)
    if ApplicationRecord.readonly?
      html_options = html_options.merge(disabled: true)
      html_options[:title] ||= "database is in read-only mode"
    end

    boom if html_options[:data] && html_options[:data][:turbo_method]

    html_options[:class] = "#{html_options[:class]} disabled:opacity-50 disabled:cursor-not-allowed"
    html_options[:method] ||= :get

    if html_options[:method] == :get and not html_options[:disabled]
      html_options.delete :method
      link_to name, path_options, html_options, &block
    else
      button_to name, path_options, html_options, &block
    end
  end

  def action_cable_meta_tag_dynamic
    scheme = (request.env['HTTP_X_FORWARDED_PROTO'] || request.env["rack.url_scheme"] || '').split(',').last
    return '' if scheme.blank?
    host = request.env['HTTP_X_FORWARDED_HOST'] || request.env["HTTP_HOST"]
    scope = request.env['RAILS_APP_SCOPE']
    root = request.env['RAILS_RELATIVE_URL_ROOT']

    if ENV['FLY_REGION'] and scope
      websocket = "#{scheme.sub('http', 'ws')}://#{host}#{root}/#{scope}/cable"
    else
      websocket = "#{scheme.sub('http', 'ws')}://#{host}#{root}/cable"
    end

    "<meta name=\"action-cable-url\" content=\"#{websocket}\" />".html_safe
  end

  def favicon_link
    root = request.env['RAILS_RELATIVE_URL_ROOT']

    favicon = "#{root}/intertwingly.png"

    "<link rel='icon' type='image/png' href='#{favicon}'>".html_safe
  end

  def showcase_logo
    "/#{EventController.logo}"
  end

  def as_pdf(options = {})
    result = options.merge(format: :pdf)
    result[:pagesize] = ENV['PAGESIZE'] if ENV['PAGESIZE']
    result
  end

  def localized_date(date_string, locale = nil)
    return date_string unless date_string.present?
    
    # Use provided locale or fall back to session/env locale
    locale ||= @locale || ENV.fetch("RAILS_LOCALE", "en_US")
    locale = locale.gsub('_', '-')
    
    # Check if it's a date range
    if date_string =~ /^(\d{4}-\d{2}-\d{2})( - (\d{4}-\d{2}-\d{2}))?$/
      start_date_str = $1
      end_date_str = $3
      
      begin
        start_date = Date.parse(start_date_str)
        
        if end_date_str
          end_date = Date.parse(end_date_str)
          format_date_range(start_date, end_date, locale)
        else
          format_single_date(start_date, locale)
        end
      rescue ArgumentError
        # Return original string if parsing fails
        date_string
      end
    else
      # Return original string if not in expected format
      date_string
    end
  end

  private

  def format_single_date(date, locale)
    # Get locale-specific month and weekday names
    month_names = localized_month_names(locale)
    weekday_names = localized_weekday_names(locale)
    
    weekday = weekday_names[date.wday]
    month = month_names[date.month - 1]
    
    # Format based on locale conventions
    case locale
    when 'en-GB', 'en-AU'
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

  def format_date_range(start_date, end_date, locale)
    year = Date.current.year
    show_year = start_date.year != year
    
    month_names = localized_month_names(locale)
    start_month = month_names[start_date.month - 1]
    end_month = month_names[end_date.month - 1]
    
    # Format based on locale conventions
    case locale
    when 'en-GB', 'en-AU'
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

  def localized_month_names(locale)
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
    else # English
      ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']
    end
  end

  def localized_weekday_names(locale)
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
    else # English
      ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
    end
  end
end
