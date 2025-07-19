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


end
