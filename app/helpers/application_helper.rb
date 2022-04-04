module ApplicationHelper
  def up_link(name, path_options, html_options = {}, &block)
    if ApplicationRecord.readonly?
      html_optinos = html_options.merge(disabled: true)
      html_options[:class] = "#{html_options[:class]} btn-disabled"
      html_options[:title] = "database is in read-only mode"
    end

    link_to name, path_options, html_options, &block
  end

  def action_cable_meta_tag_dynamic
    scheme = (request.env['HTTP_X_FORWARDED_PROTO'] || request.env["rack.url_scheme"]).split(',').last
    host = request.env['HTTP_X_FORWARDED_HOST'] || request.env["HTTP_HOST"]
    scope = request.env['RAILS_APP_SCOPE']
    root = request.env['RAILS_RELATIVE_URL_ROOT']
    websocket = "#{scheme.sub('http', 'ws')}://#{host}#{root}/cable"
    "<meta name=\"action-cable-url\" content=\"#{websocket}\" />".html_safe
  end
end
