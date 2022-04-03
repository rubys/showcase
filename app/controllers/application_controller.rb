class ApplicationController < ActionController::Base
  rescue_from ActiveRecord::ReadOnlyRecord do
    flash[:error] = 'Database is in readonly mode'
    redirect_back fallback_location: root_url,
      flash: {error: 'Database is in readonly mode'}
  end

  before_action do
    scheme = (request.env['HTTP_X_FORWARDED_PROTO'] || request.env["rack.url_scheme"]).split(',').last
    host = request.env['HTTP_X_FORWARDED_HOST'] || request.env["HTTP_HOST"]
    scope = request.env['RAILS_APP_SCOPE']
    root = request.env['RAILS_RELATIVE_URL_ROOT']
    @websocket = "#{scheme.sub('http', 'ws')}://#{host}#{root}/#{[scope, 'cable'].compact.join('/')}"
  end
end