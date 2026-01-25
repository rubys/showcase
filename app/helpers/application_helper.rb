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
    scheme = (request.env['HTTP_X_FORWARDED_PROTO'] || request.env["rack.url_scheme"] || '').split(',').last&.strip
    return '' if scheme.blank?
    host = (request.env['HTTP_X_FORWARDED_HOST'] || request.env["HTTP_HOST"]).to_s.split(',').last&.strip
    host = 'rubix.intertwingly.net' if ENV['RAILS_APP_OWNER']&.downcase == 'index'
    # Check both request.env and ENV for RAILS_APP_SCOPE
    scope = request.env['RAILS_APP_SCOPE'] || ENV['RAILS_APP_SCOPE']
    root = request.env['RAILS_RELATIVE_URL_ROOT'] || ENV['RAILS_RELATIVE_URL_ROOT']

    # Use scope in cable URL when available, not just on Fly
    # This ensures WebSocket connections work correctly with navigator
    if ENV['RAILS_CABLE_PATH']
      websocket = "#{scheme.sub('http', 'ws')}://#{host}#{ENV['RAILS_CABLE_PATH']}"
    elsif scope.present?
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
    result[:papersize] = ENV['PAPERSIZE'] if ENV['PAPERSIZE']
    result
  end

  def localized_date(date_string, locale = nil)
    return date_string unless date_string.present?
    
    # Use provided locale or fall back to session/env locale
    locale ||= @locale || ENV.fetch("RAILS_LOCALE", "en_US")
    # Convert to browser format using centralized config
    locale = Locale.to_browser_format(locale)
    
    # Check if it's a date range
    if date_string =~ /^(\d{4}-\d{2}-\d{2})( - (\d{4}-\d{2}-\d{2}))?$/
      start_date_str = $1
      end_date_str = $3
      
      begin
        start_date = Date.parse(start_date_str)
        
        if end_date_str
          end_date = Date.parse(end_date_str)
          Locale.format_date_range(start_date, end_date, locale)
        else
          Locale.format_single_date(start_date, locale)
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

  def localized_time(time, locale = nil)
    return nil unless time
    
    # Use provided locale or fall back to session/env locale
    locale ||= @locale || ENV.fetch("RAILS_LOCALE", "en_US")
    # Convert to browser format using centralized config
    locale = Locale.to_browser_format(locale)
    
    Locale.format_time(time, locale)
  end

  def localized_currency(number, locale = nil, currency = nil)
    return nil unless number
    
    # Use provided locale or fall back to session locale or env locale
    locale ||= @locale || ENV.fetch("RAILS_LOCALE", "en_US")
    # Convert to browser format using centralized config
    locale = Locale.to_browser_format(locale)
    
    # Determine currency based on locale if not provided
    if currency.nil?
      currency = case locale
      when 'ja-JP'
        'JPY'
      when 'en-GB'
        'GBP'
      when 'en-AU'
        'AUD'
      when 'en-CA', 'fr-CA'
        'CAD'
      when 'fr-FR', 'de-DE', 'es-ES', 'it-IT'
        'EUR'
      when 'pl-PL'
        'PLN'
      when 'uk-UA'
        'UAH'
      else
        'USD'
      end
    end
    
    Locale.number_format(number, locale, style: 'currency', currency: currency)
  end

  def localized_number(number, locale = nil, precision = nil)
    return nil unless number
    
    # Use provided locale or fall back to session locale or env locale
    locale ||= @locale || ENV.fetch("RAILS_LOCALE", "en_US")
    # Convert to browser format using centralized config
    locale = Locale.to_browser_format(locale)
    
    # Determine precision based on currency conventions if not provided
    if precision.nil?
      # Use 0 decimals for JPY, 2 for others
      precision = (locale == 'ja-JP') ? 0 : 2
    end
    
    # Format as decimal number without currency symbol
    Locale.number_format(number, locale, style: 'decimal',
                        minimum_fraction_digits: precision,
                        maximum_fraction_digits: precision)
  end

  def couple_names(entry_or_heat)
    entry = entry_or_heat.is_a?(Heat) ? entry_or_heat.entry : entry_or_heat

    if entry.lead.id == 0 && entry.follow.id == 0
      # Both are Nobody - formation
      entry.lead.name + ' & ' + entry.follow.name
    elsif entry.lead.id == 0
      # Lead is Nobody - follower dancing solo
      entry.follow.name + ' (Solo)'
    elsif entry.follow.id == 0
      # Follow is Nobody - leader dancing solo
      entry.lead.name + ' (Solo)'
    else
      # Regular couple
      entry.lead.name + ' & ' + entry.follow.name
    end
  end

  # Returns the number of physical ballrooms based on the event's ballroom setting
  def num_ballrooms(ballroom_setting = nil)
    ballroom_setting ||= Event.current&.ballrooms || 1
    case ballroom_setting
    when 1 then 1
    when 2, 3, 4 then 2  # split-by-role or rotating with 2 ballrooms
    when 5 then 3        # rotating with 3 ballrooms
    when 6 then 4        # rotating with 4 ballrooms
    else 2
    end
  end

  # Returns ballroom letter options based on the event's ballroom setting
  # For use in select dropdowns
  def ballroom_options(include_both: false)
    count = [num_ballrooms, Category.maximum(:ballrooms).to_i].max
    count = num_ballrooms(count) if count > 4  # handle category-level overrides
    letters = ('A'..'Z').first(count)
    return letters unless include_both

    # Display "All" instead of "Both" when there are more than 2 ballrooms
    # but keep internal value as "Both" for backwards compatibility
    display_text = count > 2 ? 'All' : 'Both'
    [[display_text, 'Both']] + letters
  end

end
