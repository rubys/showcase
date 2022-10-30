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
    scheme = (request.env['HTTP_X_FORWARDED_PROTO'] || request.env["rack.url_scheme"]).split(',').last
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
    scheme = (request.env['HTTP_X_FORWARDED_PROTO'] || request.env["rack.url_scheme"]).split(',').last
    host = request.env['HTTP_X_FORWARDED_HOST'] || request.env["HTTP_HOST"]
    scope = request.env['RAILS_APP_SCOPE']
    root = request.env['RAILS_RELATIVE_URL_ROOT']

    if scope
      favicon = "#{root}/#{scope}/intertwingly.png"
    else
      favicon = "#{root}/intertwingly.png"
    end

    "<link rel='icon' type='image/png' href='#{favicon}'>".html_safe
  end

  def showcase_logo
    "/#{EventController.logo}"
  end
end
