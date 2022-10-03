class ApplicationController < ActionController::Base
  before_action :authenticate_user

  rescue_from ActiveRecord::ReadOnlyRecord do
    flash[:error] = 'Database is in readonly mode'
    redirect_back fallback_location: root_url,
      flash: {error: 'Database is in readonly mode'}
  end

  private
    def authenticate_user
      get_authentication

      return unless Rails.env.production?
      return if request.local?

      authenticate_or_request_with_http_basic do |id, password| 
        User.authorized? @authuser
      end
    end

    def get_authentication
      if request.headers['HTTP_AUTHORIZATION']
        @authuser = Base64.decode64(request.headers['HTTP_AUTHORIZATION'].split(' ')[1]).split(':').first
      else
        @authuser = request.headers["HTTP_X_REMOTE_USER"]
        @authuser ||= ENV["HTTP_X_REMOTE_USER"]
      end
    end
end
