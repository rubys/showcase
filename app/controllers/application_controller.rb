class ApplicationController < ActionController::Base
  rescue_from ActiveRecord::ReadOnlyRecord do
    flash[:error] = 'Database is in readonly mode'
    redirect_back fallback_location: root_url,
      flash: {error: 'Database is in readonly mode'}
  end

  before_action do
    scheme = request.env['HTTP_X_FORWARDED_PROTO'] || request.env["rack.url_scheme"]
    host = request.env['HTTP_X_FORWARDED_HOST'] || request.env["HTTP_HOST"]
    script = request.env['ORIGINAL_SCRIPT_NAME'] || request.env['ORIGINAL_SCRIPT_NAME']
    @websocket = "#{scheme.sub('http', 'ws')}://#{host}#{script}/cable"
  end
end