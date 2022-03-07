module ApplicationHelper
  def up_link(name, path_options, html_options = {}, &block)
    if ApplicationRecord.readonly?
      html_optinos = html_options.merge(disabled: true)
      html_options[:class] = "#{html_options[:class]} btn-disabled"
      html_options[:title] = "database is in read-only mode"
    end

    link_to name, path_options, html_options, &block
  end
end
