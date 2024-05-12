class ApplicationController < ActionController::Base
  before_action :authenticate_user

  rescue_from ActiveRecord::ReadOnlyRecord do
    flash[:error] = 'Database is in readonly mode'
    redirect_back fallback_location: root_url,
      flash: {error: 'Database is in readonly mode'}
  end

  def self.permit_site_owners(*actions, trust_level: 0)
    skip_before_action :authenticate_user, only: actions

    if User.trust_level >= trust_level
      before_action :authenticate_site_owner, only: actions
    else
      before_action :authenticate_event_owner, only: actions
    end
  end

  private
    def authenticate_user
      return authenticate_site_owner if User.trust_level >= 75

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

    def authenticate_event_owner
      get_authentication

      unless ENV['HTTP_X_REMOTE_USER']
        return unless Rails.env.production?
        return if request.local?
      end

      return if ENV['RAILS_APP_OWNER'] == 'Demo'

      return if User.index_auth?(@authuser)

      forbidden(true) unless User.owned?(@authuser, Struct.new(:name).new(ENV['RAILS_APP_OWNER']))
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

    def forbidden(prompt = false)
      if @authuser and not params[:login] and not prompt
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
