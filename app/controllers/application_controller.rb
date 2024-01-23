class ApplicationController < ActionController::Base
  before_action :authenticate_user

  rescue_from ActiveRecord::ReadOnlyRecord do
    flash[:error] = 'Database is in readonly mode'
    redirect_back fallback_location: root_url,
      flash: {error: 'Database is in readonly mode'}
  end

  def self.permit_site_owners(*actions)
    skip_before_action :authenticate_user, only: actions
    before_action :authenticate_site_owner, only: actions
  end

  private
    def authenticate_user
      get_authentication

      unless ENV['HTTP_X_REMOTE_USER']
        return unless Rails.env.production?
        return if request.local?
      end

      return if ENV['RAILS_APP_OWNER'] == 'Demo'

      forbidden unless User.authorized?(@authuser)
    end

    def authenticate_site_owner
      get_authentication

      unless ENV['HTTP_X_REMOTE_USER']
        return unless Rails.env.production?
        return if request.local?
      end

      return if ENV['RAILS_APP_OWNER'] == 'Demo'
      return if User.authorized?(@authuser)

      forbidden unless User.owned?(@authuser, @studio)
    end

    def show_detailed_exceptions?
      User.index_auth?(@authuser)
    end

    def get_authentication
      if request.headers['HTTP_AUTHORIZATION']
        @authuser = Base64.decode64(request.headers['HTTP_AUTHORIZATION'].split(' ')[1]).split(':').first
      else
        @authuser = request.headers["HTTP_X_REMOTE_USER"]
        @authuser ||= ENV["HTTP_X_REMOTE_USER"]
      end
    end

    def forbidden
      if @authuser and not params[:login]
        page = ENV['RAILS_APP_OWNER'] == 'index' ? 'public/403-index.html' : 'public/403.html'
        render file: File.expand_path(page, Rails.root),
          layout: false, status: :forbidden
      else
        authenticate_or_request_with_http_basic do |id, password|
          false
        end
      end
    end

    def admin_home
      @home_link = admin_path
    end
end
