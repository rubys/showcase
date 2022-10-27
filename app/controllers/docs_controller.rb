class DocsController < ApplicationController
  def page
    file = Rails.root.join('app/views/docs', params[:page] + '.md')
    if File.exist? file
      render html: Kramdown::Document.new(IO.read(file)).to_html.html_safe, layout: 'docs'
    else
      raise ActionController::RoutingError.new('Not Found')
    end
  end
end