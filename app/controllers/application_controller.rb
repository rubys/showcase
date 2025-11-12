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
  # Minimum versions supporting ES2020 (esbuild target) + WebSockets
  # Import maps are polyfilled via es-module-shims for browsers in NEEDS_IMPORTMAP_SHIM range
  MODERN_BROWSER = {
    "Chrome" => 80,      # ES2020 support (February 2020)
    "Safari" => 13.1,    # ES2020 support (March 2020)
    "Firefox" => 74,     # ES2020 support (March 2020)
    "Internet Explorer" => false,
    "Opera" => 67        # ES2020 support (based on Chromium 80)
  }

  # Browsers that support ES2020 but need es-module-shims for import maps
  NEEDS_IMPORTMAP_SHIM = {
    "Chrome" => [80, 89],    # Chrome 80-88 need shim (89+ has native import maps)
    "Firefox" => [74, 108],  # Firefox 74-107 need shim (108+ has native import maps)
    "Safari" => [13.1, 16.4], # Safari 13.1-16.3 need shim (16.4+ has native import maps)
    "Opera" => [67, 76]      # Opera 67-75 need shim (76+ has native import maps)
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

  def needs_importmap_shim?
    user_agent = UserAgent.parse(request.user_agent)
    range = NEEDS_IMPORTMAP_SHIM[user_agent.browser]
    return false if range.nil?

    version = user_agent.version
    min_version = UserAgent::Version.new(range[0].to_s)
    max_version = UserAgent::Version.new(range[1].to_s)

    version >= min_version && version < max_version
  end
  helper_method :needs_importmap_shim?

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
          showcases = ShowcasesLoader.load
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
        unless User.owned?(@authuser, @studio)
          forbidden
          return
        end
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
      # In development, allow HTTP_X_REMOTE_USER to simulate authentication
      if Rails.env.development?
        @authuser = request.headers["HTTP_X_REMOTE_USER"]
        @authuser ||= ENV["HTTP_X_REMOTE_USER"]
        return nil
      end

      return nil unless Rails.env.production?
      return nil if ENV['RAILS_APP_OWNER'] == 'Demo'

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
