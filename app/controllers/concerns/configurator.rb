# RegionConfiguration will be autoloaded by Rails since we added lib to autoload_paths
require 'set'

module Configurator
  # Path constants
  DBPATH = ENV['RAILS_DB_VOLUME'] || Rails.root.join('db').to_s

  # Timeout and memory constants
  IDLE_TIMEOUT = '15m'
  STARTUP_TIMEOUT = '5s'
  DEFAULT_MEMORY_LIMIT = '768M'
  POOL_TIMEOUT = '5m'

  def generate_map
    map_data = RegionConfiguration.generate_map_data
    file = File.join(DBPATH, 'map.yml')
    RegionConfiguration.write_yaml_if_changed(file, map_data)
  end

  def generate_showcases
    showcases_data = RegionConfiguration.generate_showcases_data
    file = File.join(DBPATH, 'showcases.yml')
    RegionConfiguration.write_yaml_if_changed(file, showcases_data)
  end

  def generate_navigator_config
    config = build_navigator_config
    file = File.join(Rails.root, 'config', 'navigator.yml')
    RegionConfiguration.write_yaml_if_changed(file, config)
  end

  def generate_navigator_maintenance_config
    config = build_navigator_maintenance_config
    file = File.join(Rails.root, 'config', 'navigator-maintenance.yml')
    RegionConfiguration.write_yaml_if_changed(file, config)
  end

  private

  # Cache showcases.yml to avoid repeated file reads
  def showcases
    @showcases ||= ShowcasesLoader.load
  end

  # Add locale to tenant environment if present
  def add_locale_if_present(tenant, locale)
    tenant['env']['RAILS_LOCALE'] = locale.gsub('-', '_') if locale.present?
  end

  # Build remote proxy routes for password and studio request endpoints
  def build_remote_proxy_routes
    # Don't add reverse proxies when we ARE rubix.intertwingly.net (the origin server)
    # Only add them on Fly.io/Hetzner that need to proxy back to rubymini
    return [] if determine_host == 'rubix.intertwingly.net'

    [
      {
        'path' => '^/showcase/password(/.*)',
        'target' => 'https://rubix.intertwingly.net/showcase/password$1',
        'headers' => {
          'X-Forwarded-Host' => '$host'
        }
      },
      {
        'path' => '^/showcase/studios/([a-z]*)/request$',
        'target' => 'https://rubix.intertwingly.net/showcase/studios/$1/request',
        'headers' => {
          'X-Forwarded-Host' => '$host'
        }
      }
    ]
  end

  def build_navigator_config
    config = {
      'server' => build_server_config,
      'cable' => build_cable_config,
      'applications' => build_applications_config,
      'managed_processes' => build_managed_processes_config,
      'routes' => build_routes_config,
      'hooks' => build_hooks_config,
      'logging' => build_logging_config,
      'maintenance' => build_maintenance_config
    }

    # Add auth section if htpasswd file exists
    auth_config = build_auth_config
    config['auth'] = auth_config if auth_config

    config
  end

  def build_navigator_maintenance_config
    config = {
      'server' => build_server_config_for_maintenance,
      'managed_processes' => build_managed_processes_config_for_maintenance,
      'routes' => build_routes_config_for_maintenance,
      'maintenance' => { 'enabled' => true, 'page' => '/503.html' },
      'hooks' => build_hooks_config_for_maintenance,
      'logging' => { 'format' => 'text' }
    }

    # Add auth section if it has content
    auth_config = build_auth_config_for_maintenance
    config['auth'] = auth_config if auth_config

    config
  end

  def build_cable_config
    # TurboCable WebSocket configuration
    # Path must be the FULL path including root_path (Navigator checks full request path)
    # For Fly.io: /showcase/regions/{region}/cable
    # For local/other: /showcase/cable
    cable_path = if ENV['FLY_REGION']
                   "/showcase/regions/#{ENV['FLY_REGION']}/cable"
                 else
                   '/showcase/cable'
                 end

    {
      'enabled' => true,
      'path' => cable_path,
      'broadcast_path' => '/_broadcast'
    }
  end

  def build_server_config
    host = determine_host
    root = determine_root_path

    config = build_server_config_base(
      listen: determine_listen_port,
      hostname: host,
      root_path: root,
      public_dir: Rails.root.join('public').to_s
    )

    # Add idle configuration for Fly.io deployments
    if ENV['FLY_REGION']
      config['idle'] = {
        'action' => 'suspend',
        'timeout' => IDLE_TIMEOUT
      }
    end

    # Add bot detection configuration
    config['bot_detection'] = {
      'enabled' => true,
      'action' => 'reject'
    }

    # Add CGI scripts configuration
    config['cgi_scripts'] = build_cgi_scripts_config(root)

    config
  end

  def build_server_config_base(listen:, hostname:, root_path:, public_dir:)
    # Core server configuration shared by both full and maintenance configs
    config = {
      'listen' => listen,
      'hostname' => hostname,
      'root_path' => root_path,
      'static' => build_static_config(public_dir, root_path),
      'health_check' => build_health_check_config
    }

    # rubymini runs behind Apache reverse proxy on rubix.intertwingly.net
    # Enable trust_proxy so Navigator preserves X-Forwarded-Host from Apache
    # This is required for Rails CSRF protection to see the correct origin
    config['trust_proxy'] = true if rubymini?

    config
  end

  def build_static_config(public_dir, root)
    # Static file configuration shared by both full and maintenance configs
    {
      'public_dir' => public_dir,
      'allowed_extensions' => %w[html htm txt xml json css js map png jpg gif svg ico pdf xlsx],
      'try_files' => %w[index.html .html .htm],
      'normalize_trailing_slashes' => true,
      'cache_control' => build_cache_control(root)
    }
  end

  def build_health_check_config
    # Synthetic health check configuration
    # Returns a 200 OK response without proxying to Rails applications
    {
      'path' => '/up',
      'response' => {
        'status' => 200,
        'body' => 'OK',
        'headers' => {
          'Content-Type' => 'text/plain'
        }
      }
    }
  end

  def build_server_config_for_maintenance
    # Generate environment-specific maintenance config
    # Fly.io/Kamal: production container paths
    # rubymini: admin server paths
    # Otherwise: local development paths

    if rubymini?
      # rubymini admin server
      listen = determine_listen_port
      hostname = determine_host
      root = determine_root_path
      public_dir = Rails.root.join('public').to_s
      production = false
    elsif ENV['FLY_APP_NAME'] || ENV['KAMAL_CONTAINER_NAME']
      # Production containers (Fly.io or Kamal)
      listen = 3000
      hostname = 'localhost'
      root = '/showcase'
      public_dir = 'public'
      production = true
    else
      # Local development
      listen = determine_listen_port
      hostname = determine_host
      root = determine_root_path
      public_dir = Rails.root.join('public').to_s
      production = false
    end

    config = build_server_config_base(
      listen: listen,
      hostname: hostname,
      root_path: root,
      public_dir: public_dir
    )

    # Add CGI scripts configuration
    config['cgi_scripts'] = build_cgi_scripts_config(root, production: production)

    config
  end

  def build_public_paths(root)
    # Public paths that don't require authentication
    # Used by both full and maintenance auth configs
    [
      "#{root}/assets/",
      "#{root}/cable",
      "#{root}/demo/",
      "#{root}/docs/",
      "#{root}/events/console",
      "#{root}/password/",
      "#{root}/regions/",
      "#{root}/studios/",
      "#{root}/index_date",
      "#{root}/update_config",  # CGI endpoint for configuration updates
      '/favicon.ico',
      '/robots.txt',
      '/up',  # Health check endpoint for Kamal
      '*.css',
      '*.gif',
      '*.ico',
      '*.jpg',
      '*.js',
      '*.png',
      '*.svg',
      '*.webp'
    ]
  end

  def build_auth_config
    htpasswd_path = File.join(DBPATH, 'htpasswd')
    root = determine_root_path

    # Only return auth config if htpasswd file exists
    return nil unless File.exist?(htpasswd_path)

    public_paths = build_public_paths(root)

    # Build auth_patterns for studio index pages and tenant public paths
    # Use grouped alternations for better performance (fewer regex patterns to check)
    auth_patterns = []

    # Add exact match for root path (redirects to /showcase/studios/)
    auth_patterns << {
      'pattern' => '^/$',
      'action' => 'off'
    }

    # Add region-specific public paths that need regex for all regions
    if ENV['FLY_REGION']
      # Get list of all regions from map.yml
      map_file = File.join(Rails.root, 'config/tenant/map.yml')
      regions = File.exist?(map_file) ? (YAML.load_file(map_file).dig('regions')&.keys || []) : []

      # Create alternation pattern for all regions
      regions_pattern = regions.map { |r| Regexp.escape(r) }.join('|')

      if regions_pattern.present?
        # Allow cable WebSocket connections for all regions: /showcase/regions/(iad|ewr|ord|...)/cable
        auth_patterns << {
          'pattern' => "^#{Regexp.escape(root)}/regions/(?:#{regions_pattern})/cable$",
          'action' => 'off'
        }

        # Allow demo paths for all regions: /showcase/regions/(iad|ewr|ord|...)/demo/
        auth_patterns << {
          'pattern' => "^#{Regexp.escape(root)}/regions/(?:#{regions_pattern})/demo/",
          'action' => 'off'
        }
      end
    end

    # Use shared module to get prerenderable paths
    # Only multi-event studios (with :events) have prerendered public indexes
    paths = PrerenderConfiguration.prerenderable_paths(showcases)

    # Create one pattern per year for studio index pages: /showcase/2025/raleigh/?
    paths[:multi_event_studios].each do |year, tokens|
      escaped_tokens = tokens.map { |t| Regexp.escape(t) }.join('|')
      auth_patterns << {
        'pattern' => "^#{Regexp.escape(root)}/#{year}/(?:#{escaped_tokens})/?$",
        'action' => 'off'
      }
    end

    # Create one pattern per year for tenant public paths: /showcase/2025/raleigh/disney/public/*
    tenant_public_paths_by_year = {}
    showcases.each do |year, sites|
      sites.each do |token, info|
        if info[:events]
          tenant_public_paths_by_year[year] ||= []
          info[:events].each do |subtoken, _subinfo|
            tenant_public_paths_by_year[year] << "#{token}/#{subtoken}"
          end
        end
      end
    end

    tenant_public_paths_by_year.each do |year, tenant_event_combos|
      escaped_combos = tenant_event_combos.map { |combo| Regexp.escape(combo) }.join('|')
      auth_patterns << {
        'pattern' => "^#{Regexp.escape(root)}/#{year}/(?:#{escaped_combos})/public/",
        'action' => 'off'
      }
    end

    {
      'enabled' => true,
      'realm' => 'Showcase',
      'htpasswd' => htpasswd_path,
      'public_paths' => public_paths,
      'auth_patterns' => auth_patterns
    }
  end

  def build_cache_control(root)
    {
      'overrides' => [
        { 'path' => "#{root}/assets/", 'max_age' => '24h' },
        { 'path' => "#{root}/", 'max_age' => '24h' }
      ]
    }
  end

  def build_cgi_scripts_config(root, production: false)
    scripts = []

    # Determine paths based on environment
    if production
      # Production containers (Fly.io/Kamal) - use container paths
      db_volume = '/data/db'
      script_path = '/rails/script/update_configuration.rb'
      rails_env = 'production'
    else
      # rubymini or local development - use Rails.root paths
      db_volume = ENV['RAILS_DB_VOLUME'] || Rails.root.join('db').to_s
      script_path = Rails.root.join('script/update_configuration.rb').to_s
      rails_env = 'production'
    end

    reload_target = 'config/navigator.yml'

    # Add configuration update CGI script (publicly accessible)
    # Runs as root to allow rsync and config reload operations
    scripts << {
      'path' => "#{root}/update_config",
      'script' => script_path,
      'method' => 'POST',
      'user' => 'root',
      'group' => 'root',
      'timeout' => '5m',
      'reload_config' => reload_target,
      'env' => {
        'RAILS_DB_VOLUME' => db_volume,
        'RAILS_ENV' => rails_env
      }
    }

    scripts
  end



  def build_routes_config
    root = determine_root_path
    region = ENV['FLY_REGION']

    routes = {
      'redirects' => [],
      'rewrites' => [],
      'reverse_proxies' => [],
      'fly' => {
        'replay' => []
      }
    }

    # Add redirects
    if region
      routes['redirects'] << { 'from' => '^/$', 'to' => "#{root}/studios/" }
      routes['redirects'] << { 'from' => "^#{root}/demo/?$", 'to' => "#{root}/regions/#{region}/demo/" }
    elsif root != ''
      routes['redirects'] << { 'from' => '^/(showcase)?$', 'to' => "#{root}/studios/" }
    else
      routes['redirects'] << { 'from' => '^/$', 'to' => "#{root}/studios/" }
    end
    
    # Add rewrites
    if root != ''
      routes['rewrites'] << { 'from' => '^/assets/(.*)', 'to' => "#{root}/assets/$1" }
      # Add rewrite for root-level static files (images, etc.)
      # Match files that don't already have the showcase prefix
      # Go regexp doesn't support negative lookahead, so we'll use a simpler pattern
      # that just matches root-level image files
      routes['rewrites'] << { 'from' => '^/([^/]+\.(gif|png|jpg|jpeg|ico|pdf|svg|webp|txt))$', 'to' => "#{root}/$1" }
    end
    
    # Add proxy routes for remote services
    routes['reverse_proxies'].concat(build_remote_proxy_routes)
    
    # Add PDF and XLSX generation routing to smooth-pdf app
    # Navigator supports three types of fly-replay routing:
    # 1. App-based: { 'app' => 'smooth-pdf' } -> routes to any instance of smooth-pdf app
    # 2. Machine-based: { 'machine' => 'machine_id', 'app' => 'smooth-pdf' } -> routes to specific machine instance
    # 3. Region-based: { 'region' => 'iad' } -> routes to specific region
    if ENV['FLY_APP_NAME']
      routes['fly']['replay'] << {
        'path' => "^#{root}/.+\\.pdf$",
        'app' => 'smooth-pdf',
        'status' => 307
      }

      routes['fly']['replay'] << {
        'path' => "^#{root}/.+\\.xlsx$",
        'app' => 'smooth-pdf',
        'status' => 307
      }
    end
    
    # Add fly-replay and reverse proxy support for cross-region events
    if region && ENV['FLY_APP_NAME']
      add_cross_region_routing(routes, root, region)
    end
    
    routes
  end

  def add_cross_region_routing(routes, root, current_region)
    # Use shared module to group studios by region and type
    # Need year-specific grouping because same studio can be multi-event in one year, single-tenant in another
    regions = PrerenderConfiguration.studios_by_region_and_type(showcases, current_region)

    # Add region-specific fly-replay routes (excluding static index pages)
    regions.keys.each do |target_region|
      routes['fly']['replay'] << {
        'path' => "^#{root}/regions/#{target_region}/.+$",
        'region' => target_region,
        'status' => 307
      }
    end

    # Add studio-specific routing for each region
    regions.each do |target_region, data|
      # Multi-event studios (with :events) have prerendered indexes
      # Pattern excludes /year/studio/ but includes /year/studio/anything
      data[:multi_event].each do |year, tokens|
        sites = tokens.sort.join('|')
        routes['fly']['replay'] << {
          'path' => "^#{root}/(?:#{year})/(?:#{sites})/.+$",
          'region' => target_region,
          'status' => 307
        }
      end

      # Single-tenant studios (no :events) don't have prerendered indexes
      # Pattern includes /year/studio/ and /year/studio/anything
      data[:single_tenant].each do |year, tokens|
        sites = tokens.sort.join('|')
        routes['fly']['replay'] << {
          'path' => "^#{root}/(?:#{year})/(?:#{sites})(?:/.*)?$",
          'region' => target_region,
          'status' => 307
        }
      end
    end
  end

  def build_applications_config
    tenants = build_tenants_list

    {
      'framework' => build_framework_config,
      'env' => build_application_env,
      'health_check' => '/up',
      'startup_timeout' => STARTUP_TIMEOUT,
      'track_websockets' => false,  # WebSockets proxied to standalone Action Cable server
      'tenants' => tenants,
      'pools' => build_pools_config
    }
  end

  def build_pools_config
    config = {
      'max_size' => calculate_pool_size,
      'timeout' => POOL_TIMEOUT,
      'start_port' => 4000
    }

    # Add memory limits and user/group isolation for Fly.io and Kamal (Linux) deployments
    if ENV['FLY_REGION'] || ENV['KAMAL_CONTAINER_NAME']
      config['default_memory_limit'] = DEFAULT_MEMORY_LIMIT
      config['user'] = 'rails'
      config['group'] = 'rails'
    end

    config
  end

  def calculate_pool_size
    mem = if File.exist?('/proc/meminfo')
            IO.read('/proc/meminfo')[/\d+/].to_i
          else
            `sysctl -n hw.memsize`.to_i / 1024
          end
    6 + mem / 1024 / 1024
  rescue StandardError => e
    Rails.logger.warn("Failed to calculate pool size: #{e.message}, using default of 10")
    10
  end
  
  def build_framework_config
    {
      'command' => 'bin/rails',
      'args' => ['server', '-p', '${port}'],
      'app_directory' => '/rails',
      'port_env_var' => 'PORT',
      'start_delay' => '2s'
    }
  end

  def build_application_env
    storage = ENV['RAILS_STORAGE'] || Rails.root.join('storage').to_s
    dbpath = ENV['RAILS_DB_VOLUME'] || Rails.root.join('db').to_s
    root = determine_root_path

    env = {}

    # Global environment variables (no substitution needed)
    if root != ''
      env['RAILS_RELATIVE_URL_ROOT'] = root
    end

    # Enable JSON logging for navigator-managed apps
    env['RAILS_LOG_JSON'] = 'true'

    # TurboCable WebSocket configuration
    # RAILS_CABLE_PATH: Where clients connect (handled by Navigator)
    # TURBO_CABLE_BROADCAST_URL: Where Rails broadcasts (Navigator's /_broadcast endpoint)
    if ENV['FLY_REGION']
      env['RAILS_CABLE_PATH'] = "/showcase/regions/#{ENV['FLY_REGION']}/cable"
    else
      env['RAILS_CABLE_PATH'] = '/showcase/cable'
    end

    # Point broadcasts to Navigator's /_broadcast endpoint
    # Use localhost:3000 for production (Fly.io/Kamal), localhost:9999 for local development
    broadcast_port = ENV['FLY_APP_NAME'] || ENV['KAMAL_CONTAINER_NAME'] ? '3000' : '9999'
    env['TURBO_CABLE_BROADCAST_URL'] = "http://localhost:#{broadcast_port}/_broadcast"

    # puma and Active Record pool size
    env['RAILS_MAX_THREADS'] = '3'

    # Template variables (need substitution)
    env['RAILS_APP_DB'] = '${database}'
    env['RAILS_STORAGE'] = storage
    env['DATABASE_URL'] = "sqlite3://#{dbpath}/${database}.sqlite3"
    env['PIDFILE'] = "#{Rails.root}/tmp/pids/${database}.pid"

    env
  end

  def build_tenants_list
    region = ENV['FLY_REGION']
    dbpath = ENV['RAILS_DB_VOLUME'] || Rails.root.join('db').to_s
    storage = ENV['RAILS_STORAGE'] || Rails.root.join('storage').to_s
    root = determine_root_path

    tenants = []

    # Add index tenant
    tenants << {
      'path' => root.empty? ? '/' : "#{root}/",
      'var' => {
        'database' => 'index'
      },
      'env' => {
        'RAILS_APP_OWNER' => 'Index',
        'RAILS_SERVE_STATIC_FILES' => 'true'
      }
    }


    # Add demo tenant if in a region
    if region || ENV['KAMAL_CONTAINER_NAME']
      tenants << {
        'path' => region ? "#{root}/regions/#{region}/demo/" : "/demo/",
        'root' => "/rails/",
        'var' => {
          'database' => 'demo'
        },
        'env' => {
          'RAILS_APP_OWNER' => 'Demo',
          'RAILS_APP_SCOPE' => region ? "regions/#{region}/demo" : "demo",
          'SHOWCASE_LOGO' => 'intertwingly.png',
          'DATABASE_URL' => "sqlite3:///demo/db/demo.sqlite3",
          'RAILS_STORAGE' => '/demo/storage/demo'
        },
        'bot_detection' => {
          'enabled' => true,
          'action' => 'ignore'  # Allow bots on demo tenant for search engine indexing
        }
      }
    end
    
    # Add showcase tenants
    showcases.each do |year, sites|
      sites.each do |token, info|
        next if region && info[:region] && region != info[:region]
        
        if info[:events]
          info[:events].each do |subtoken, subinfo|
            tenant = {
              'path' => "#{root}/#{year}/#{token}/#{subtoken}/",
              'var' => {
                'database' => "#{year}-#{token}-#{subtoken}"
              },
              'env' => {
                'RAILS_APP_OWNER' => info[:name],
                'RAILS_APP_SCOPE' => "#{year}/#{token}/#{subtoken}",
                'SHOWCASE_LOGO' => info[:logo] || 'arthur-murray-logo.gif'
              }
            }

            add_locale_if_present(tenant, info[:locale])
            tenants << tenant
          end
        else
          tenant = {
            'path' => "#{root}/#{year}/#{token}/",
            'var' => {
              'database' => "#{year}-#{token}"
            },
            'env' => {
              'RAILS_APP_OWNER' => info[:name],
              'RAILS_APP_SCOPE' => "#{year}/#{token}",
              'SHOWCASE_LOGO' => info[:logo] || 'arthur-murray-logo.gif'
            }
          }

          add_locale_if_present(tenant, info[:locale])
          tenants << tenant
        end
      end
    end

    # Write out a list of database files for bin/prerender
    tenant_lists = File.open(Rails.root.join('tmp/tenants.list'), 'w')
    tenants.each do |t|
      db = t.dig('var', 'database') || t.dig('env', 'RAILS_APP_DB')
      next unless db
      tenant_lists.puts "#{dbpath}/#{db}.sqlite3"
    end
    tenant_lists.close

    tenants
  end

  def build_logging_config
    {
      'format' => 'json'
    }
  end

  def build_maintenance_config
    {
      'page' => '/503.html'
    }
  end

  def rubymini?
    require 'socket'
    Socket.gethostname == 'rubymini'
  end

  def determine_host
    if ENV['FLY_APP_NAME']
      "#{ENV['FLY_APP_NAME']}.fly.dev"
    elsif `hostname` =~ /^ubuntu/ || ENV['KAMAL_CONTAINER_NAME']
      'hetzner.intertwingly.net'
    else
      'rubix.intertwingly.net'
    end
  end

  def determine_listen_port
    # Allow override for testing (e.g., NAVIGATOR_PORT=9998)
    return ENV['NAVIGATOR_PORT'].to_i if ENV['NAVIGATOR_PORT']

    if ENV['FLY_APP_NAME'] || ENV['KAMAL_CONTAINER_NAME']
      3000
    else
      9999
    end
  end

  def determine_root_path
    ENV['KAMAL_CONTAINER_NAME'] ? '' : '/showcase'
  end

  def determine_papersize
    region = ENV['FLY_REGION']
    return 'letter' unless region

    maps_file = File.join(Rails.root, 'config/tenant/map.yml')
    return 'letter' unless File.exist?(maps_file)

    map = YAML.load_file(maps_file).dig('regions', region, 'map') rescue 'us'
    (map || 'us') == 'us' ? 'letter' : 'a4'
  end

  def load_studios
    showcases.values.map(&:keys).flatten.uniq.sort
  end

  def build_managed_processes_config
    # TurboCable provides in-process WebSocket handling via Rack middleware
    # No need for standalone Action Cable server or Redis
    []
  end

  def build_managed_processes_config_for_maintenance
    # No managed processes needed during maintenance mode
    # Action Cable not required since dynamic requests are blocked
    []
  end

  def build_routes_config_for_maintenance
    # Routes for maintenance config - excludes Action Cable
    # since WebSocket connections are not needed during maintenance
    root = '/showcase'

    routes = {
      'redirects' => [],
      'rewrites' => [],
      'reverse_proxies' => [],
      'fly' => {
        'replay' => []
      }
    }

    # Add redirects
    routes['redirects'] << { 'from' => '^/(showcase)?$', 'to' => "#{root}/studios/" }

    # Add rewrites
    routes['rewrites'] << { 'from' => '^/assets/(.*)', 'to' => "#{root}/assets/$1" }
    routes['rewrites'] << { 'from' => '^/([^/]+\.(gif|png|jpg|jpeg|ico|pdf|svg|webp|txt))$', 'to' => "#{root}/$1" }

    # Add proxy routes for remote services (excluding Action Cable)
    routes['reverse_proxies'].concat(build_remote_proxy_routes)

    routes
  end

  def build_hooks_config
    hooks = {
      'server' => {
        'start' => [],
        'ready' => [],
        'stop' => [],
        'idle' => [],
        'resume' => []
      },
      'tenant' => {
        'start' => [],
        'stop' => []
      }
    }

    # Add system configuration and htpasswd update hooks on server start if running on Fly.io
    if ENV['FLY_REGION']
      # System configuration (Redis memory overcommit, etc.)
      hooks['server']['start'] << {
        'command' => '/rails/script/hook_navigator_start.sh',
        'args' => [],
        'timeout' => '10s'
      }

      # Update htpasswd from index database
      htpasswd_hook = {
        'command' => '/rails/script/update_htpasswd.rb',
        'args' => [],
        'timeout' => '30s'
      }

      hooks['server']['start'] << htpasswd_hook

      # Full initialization on resume (sync from S3, update htpasswd, regen config)
      # Uses --safe mode to prevent stale machines from uploading outdated data
      hooks['server']['resume'] << {
        'command' => 'ruby',
        'args' => ['script/nav_initialization.rb'],
        'timeout' => '5m',
        'reload_config' => 'config/navigator.yml'
      }

      # Add ready hook for optimizations (runs after initial start and config reloads)
      # This hook handles slow operations like prerendering and event database downloads
      # that should run asynchronously while Navigator serves requests
      hooks['server']['ready'] << {
        'command' => '/rails/script/ready.sh',
        'args' => [],
        'timeout' => '10m'
      }

      # Navigator idle/stop hook - syncs all databases
      navigator_hook = {
        'command' => '/rails/script/hook_navigator_idle.sh',
        'args' => [],
        'timeout' => '5m'
      }

      # Add the same hook for both idle and stop events
      hooks['server']['idle'] << navigator_hook
      hooks['server']['stop'] << navigator_hook

      # App idle hook - syncs individual database
      hooks['tenant']['stop'] << {
        'command' => '/rails/script/hook_app_idle.sh',
        'args' => [],
        'timeout' => '2m'
      }
    end

    hooks
  end

  def build_auth_config_for_maintenance
    # Maintenance config serves only public/503.html without authentication
    # No auth required - all requests should get the maintenance page
    nil
  end

  def build_hooks_config_for_maintenance
    # Minimal hooks for maintenance mode - only ready hook for initialization
    ready_hooks = [
      {
        'command' => 'ruby',
        'args' => ['script/nav_initialization.rb'],
        'timeout' => '5m',
        'reload_config' => 'config/navigator.yml'
      }
    ]

    # rubymini needs assets precompiled on startup since they're not baked into a Docker image
    # This runs after nav_initialization.rb but before the config reload
    if rubymini?
      ready_hooks << {
        'command' => 'bin/rails',
        'args' => ['assets:precompile'],
        'env' => {
          'RAILS_ENV' => 'production',
          'RAILS_RELATIVE_URL_ROOT' => '/showcase',
          'PATH' => ENV['PATH']
        },
        'timeout' => '2m'
      }
    end

    hooks = {
      'server' => {
        'ready' => ready_hooks
      }
    }

    hooks
  end
end
