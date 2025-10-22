class ApplicationController < ActionController::Base
  before_action :authenticate_user
  before_action :current_event
  before_action :set_locale

  @@htpasswd = nil

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

  # https://github.com/rails/rails/blob/main/actionpack/lib/action_controller/metal/allow_browser.rb
  MODERN_BROWSER = {
    "Chrome" => 119,
    "Safari" => 17.2,
    "Firefox" => 121,
    "Internet Explorer" => false,
    "Opera" => 104
  }

  def browser_warn
    user_agent = UserAgent.parse(request.user_agent)
    min_version = MODERN_BROWSER[user_agent.browser]
    return if min_version == nil
    if min_version == false || user_agent.version < UserAgent::Version.new(min_version.to_s)
      browser = "You are running #{user_agent.browser} #{user_agent.version}."
      if user_agent.browser == 'Safari' and user_agent.platform == 'Macintosh'
        "#{browser} Please upgrade your operating system or swtich to a different browser."
      else
        "#{browser} Please upgrade your browser."
      end
    end
  end

  private
    def current_event
      Event.current = Event.sole
    end

    def set_locale
      @locale = if Event.current&.location.respond_to?(:locale)
        Event.current.location.locale
      elsif Rails.env.development? && ENV['RAILS_APP_DB'] =~ /^(\d+)-(\w+)-/
        begin
          year = $1.to_i
          site = $2
          showcases = YAML.load_file('config/tenant/showcases.yml')
          showcases.dig(year, site, :locale) || ENV.fetch("RAILS_LOCALE", "en_US")
        rescue => e
          ENV.fetch("RAILS_LOCALE", "en_US")
        end
      else
        ENV.fetch("RAILS_LOCALE", "en_US")
      end
    end

    def authenticate_user
      return authenticate_site_owner if User.trust_level >= 75

      get_authentication

      unless ENV['HTTP_X_REMOTE_USER']
        return unless Rails.env.production?
        return if request.local?
      end

      return if ENV['RAILS_APP_OWNER'] == 'Demo'

      unless User.authorized?(@authuser)
        # Refresh cache and try one more time before failing
        User.reload_auth
        return forbidden unless User.authorized?(@authuser)
      end
    end

    def authenticate_site_owner
      get_authentication

      unless ENV['HTTP_X_REMOTE_USER']
        return unless Rails.env.production?
        return if request.local?
      end

      return if ENV['RAILS_APP_OWNER'] == 'Demo'
      return if User.authorized?(@authuser)

      unless User.owned?(@authuser, @studio)
        # Refresh cache and try one more time before failing
        User.reload_auth
        return if User.authorized?(@authuser)
        return forbidden unless User.owned?(@authuser, @studio)
      end
    end

    def authenticate_event_owner
      get_authentication

      unless ENV['HTTP_X_REMOTE_USER']
        return unless Rails.env.production?
        return if request.local?
      end

      return if ENV['RAILS_APP_OWNER'] == 'Demo'

      return if User.authorized?(@authuser)

      owner_struct = Struct.new(:name).new(ENV['RAILS_APP_OWNER'])
      unless User.owned?(@authuser, owner_struct)
        # Refresh cache and try one more time before failing
        User.reload_auth
        return if User.authorized?(@authuser)
        return forbidden(true) unless User.owned?(@authuser, owner_struct)
      end
    end

    def show_detailed_exceptions?
      User.index_auth?(@authuser)
    end

    def get_authentication
      return nil unless Rails.env.production?
      return nil if ENV['RAILS_APP_OWNER'] == 'Demo'

      # @authuser = request.headers["HTTP_X_REMOTE_USER"]
      # @authuser ||= ENV["HTTP_X_REMOTE_USER"]
      authenticate_or_request_with_http_basic do |id, password|
        # Trim whitespace from username to handle malformed htpasswd entries
        id = id.strip
        @authuser = id

        # Check if user exists before attempting authentication
        # This prevents HTAuth::PasswdFileError exceptions for non-existent users
        if @@htpasswd&.has_entry?(id)
          authenticated = @@htpasswd.authenticated?(id, password)
          Rails.logger.info "Auth attempt: id=#{id.inspect}, has_entry=true, authenticated=#{authenticated.inspect}"
          return true if authenticated
        else
          Rails.logger.info "Auth attempt: id=#{id.inspect}, has_entry=false (cache)"
        end

        # Reload htpasswd file and try again
        dbpath = ENV.fetch('RAILS_DB_VOLUME') { 'db' }
        htpasswd_file = "#{dbpath}/htpasswd"
        @@htpasswd = HTAuth::PasswdFile.open(htpasswd_file)

        # Check again after reload
        if @@htpasswd.has_entry?(id)
          authenticated = @@htpasswd.authenticated?(id, password)
          Rails.logger.info "Auth retry: id=#{id.inspect}, has_entry=true, authenticated=#{authenticated.inspect}"
          authenticated
        else
          Rails.logger.info "Auth retry: id=#{id.inspect}, has_entry=false (reload)"
          false
        end
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
