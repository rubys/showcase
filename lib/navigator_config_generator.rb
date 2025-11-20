# frozen_string_literal: true

# Standalone navigator config generator - no Rails dependency
# Extracted from app/controllers/concerns/configurator.rb for use in scripts

require 'set'
require 'socket'
require_relative 'showcases_loader'
require_relative 'prerender_configuration'
require_relative 'region_configuration'

module NavigatorConfigGenerator
  extend self

  # Timeout and memory constants
  IDLE_TIMEOUT = '15m'
  STARTUP_TIMEOUT = '5s'
  DEFAULT_MEMORY_LIMIT = '768M'
  POOL_TIMEOUT = '5m'

  def generate_navigator_config
    config = build_navigator_config
    file = File.join(root_path, 'config', 'navigator.yml')
    write_yaml_if_changed(file, config)
  end

  private

  def root_path
    ShowcasesLoader.root_path
  end

  def db_path
    ShowcasesLoader.db_path
  end

  # Cache showcases.yml to avoid repeated file reads
  def showcases
    @showcases ||= ShowcasesLoader.load
  end

  # Add locale to tenant environment if present
  def add_locale_if_present(tenant, locale)
    tenant['env']['RAILS_LOCALE'] = locale.gsub('-', '_') if locale && !locale.empty?
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

  def build_cable_config
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
      public_dir: File.join(root_path, 'public')
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
    config = {
      'listen' => listen,
      'hostname' => hostname,
      'root_path' => root_path,
      'static' => build_static_config(public_dir, root_path),
      'health_check' => build_health_check_config
    }

    config['trust_proxy'] = true if rubymini?

    config
  end

  def build_static_config(public_dir, root)
    {
      'public_dir' => public_dir,
      'allowed_extensions' => %w[html htm txt xml json css js map png jpg gif svg ico pdf xlsx],
      'try_files' => %w[index.html .html .htm],
      'normalize_trailing_slashes' => true,
      'cache_control' => build_cache_control(root)
    }
  end

  def build_health_check_config
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

  def build_public_paths(root)
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
      "#{root}/update_config",
      '/favicon.ico',
      '/robots.txt',
      '/up',
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
    htpasswd_path = File.join(db_path, 'htpasswd')
    root = determine_root_path

    return nil unless File.exist?(htpasswd_path)

    public_paths = build_public_paths(root)
    auth_patterns = []

    auth_patterns << {
      'pattern' => '^/$',
      'action' => 'off'
    }

    if ENV['FLY_REGION']
      regions = Set.new
      showcases.each do |_year, sites|
        sites.each do |_token, info|
          regions << info[:region] if info[:region]
        end
      end
      regions = regions.to_a

      regions_pattern = regions.map { |r| Regexp.escape(r) }.join('|')

      if !regions_pattern.empty?
        auth_patterns << {
          'pattern' => "^#{Regexp.escape(root)}/regions/(?:#{regions_pattern})/cable$",
          'action' => 'off'
        }

        auth_patterns << {
          'pattern' => "^#{Regexp.escape(root)}/regions/(?:#{regions_pattern})/demo/",
          'action' => 'off'
        }
      end
    end

    paths = PrerenderConfiguration.prerenderable_paths(showcases)

    paths[:multi_event_studios].each do |year, tokens|
      escaped_tokens = tokens.map { |t| Regexp.escape(t) }.join('|')
      auth_patterns << {
        'pattern' => "^#{Regexp.escape(root)}/#{year}/(?:#{escaped_tokens})/?$",
        'action' => 'off'
      }
    end

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

    if production
      db_volume = '/data/db'
      script_path = '/rails/script/update_configuration.rb'
      rails_env = 'production'
    else
      db_volume = ENV['RAILS_DB_VOLUME'] || File.join(root_path, 'db')
      script_path = File.join(root_path, 'script/update_configuration.rb')
      rails_env = 'production'
    end

    reload_target = 'config/navigator.yml'

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

    if region
      routes['redirects'] << { 'from' => '^/$', 'to' => "#{root}/studios/" }
      routes['redirects'] << { 'from' => "^#{root}/demo/?$", 'to' => "#{root}/regions/#{region}/demo/" }
    elsif root != ''
      routes['redirects'] << { 'from' => '^/(showcase)?$', 'to' => "#{root}/studios/" }
    else
      routes['redirects'] << { 'from' => '^/$', 'to' => "#{root}/studios/" }
    end

    if root != ''
      routes['rewrites'] << { 'from' => '^/assets/(.*)', 'to' => "#{root}/assets/$1" }
      routes['rewrites'] << { 'from' => '^/([^/]+\.(gif|png|jpg|jpeg|ico|pdf|svg|webp|txt))$', 'to' => "#{root}/$1" }
    end

    routes['reverse_proxies'].concat(build_remote_proxy_routes)

    if determine_host == 'rubix.intertwingly.net'
      routes['reverse_proxies'] << {
        'path' => "^#{root}/logs(/.*)?$",
        'target' => 'http://localhost:9001$1',
        'strip_path' => true,
        'websocket' => true
      }
    end

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

    if region && ENV['FLY_APP_NAME']
      add_cross_region_routing(routes, root, region)
    end

    routes
  end

  def add_cross_region_routing(routes, root, current_region)
    regions = PrerenderConfiguration.studios_by_region_and_type(showcases, current_region)

    regions.keys.each do |target_region|
      routes['fly']['replay'] << {
        'path' => "^#{root}/regions/#{target_region}/.+$",
        'region' => target_region,
        'status' => 307
      }
    end

    regions.each do |target_region, data|
      data[:multi_event].each do |year, tokens|
        sites = tokens.sort.join('|')
        routes['fly']['replay'] << {
          'path' => "^#{root}/(?:#{year})/(?:#{sites})/.+$",
          'region' => target_region,
          'status' => 307
        }
      end

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
      'track_websockets' => false,
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
  rescue StandardError
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
    storage = ENV['RAILS_STORAGE'] || File.join(root_path, 'storage')
    dbpath = ENV['RAILS_DB_VOLUME'] || File.join(root_path, 'db')
    root = determine_root_path

    env = {}

    env['RAILS_ENV'] = 'production'

    if root != ''
      env['RAILS_RELATIVE_URL_ROOT'] = root
    end

    env['RAILS_LOG_JSON'] = 'true'

    if ENV['FLY_REGION']
      env['RAILS_CABLE_PATH'] = "/showcase/regions/#{ENV['FLY_REGION']}/cable"
    else
      env['RAILS_CABLE_PATH'] = '/showcase/cable'
    end

    env['TURBO_CABLE_BROADCAST_URL'] = "http://localhost:9999/_broadcast"
    env['RAILS_MAX_THREADS'] = '3'
    env['RAILS_APP_DB'] = '${database}'
    env['RAILS_STORAGE'] = storage
    env['DATABASE_URL'] = "sqlite3://#{dbpath}/${database}.sqlite3"
    env['PIDFILE'] = "#{root_path}/tmp/pids/${database}.pid"

    env
  end

  def build_tenants_list
    region = ENV['FLY_REGION']
    dbpath = ENV['RAILS_DB_VOLUME'] || File.join(root_path, 'db')
    root = determine_root_path

    tenants = []

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
          'action' => 'ignore'
        }
      }
    end

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
    tenant_lists = File.open(File.join(root_path, 'tmp/tenants.list'), 'w')
    tenants.each do |t|
      db = t.dig('var', 'database') || t.dig('env', 'RAILS_APP_DB')
      next unless db
      tenant_lists.puts "#{dbpath}/#{db}.sqlite3"
    end
    tenant_lists.close

    tenants
  end

  def build_logging_config
    config = { 'format' => 'json' }

    if rubymini?
      vector_config_path = File.join(root_path, 'config', 'vector.toml')
      vector_socket_path = '/tmp/navigator-vector.sock'

      config['vector'] = {
        'enabled' => true,
        'socket' => vector_socket_path,
        'config' => vector_config_path
      }
    end

    config
  end

  def build_maintenance_config
    {
      'page' => '/503.html'
    }
  end

  def rubymini?
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
    return ENV['NAVIGATOR_PORT'].to_i if ENV['NAVIGATOR_PORT']
    9999
  end

  def determine_root_path
    ENV['KAMAL_CONTAINER_NAME'] ? '' : '/showcase'
  end

  def build_managed_processes_config
    []
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

    if ENV['FLY_REGION']
      hooks['server']['start'] << {
        'command' => '/rails/script/hook_navigator_start.sh',
        'args' => [],
        'timeout' => '10s'
      }

      htpasswd_hook = {
        'command' => '/rails/script/update_htpasswd.rb',
        'args' => [],
        'timeout' => '30s'
      }

      hooks['server']['start'] << htpasswd_hook

      hooks['server']['resume'] << {
        'command' => 'ruby',
        'args' => ['script/nav_initialization.rb'],
        'timeout' => '5m',
        'reload_config' => 'config/navigator.yml'
      }

      hooks['server']['ready'] << {
        'command' => '/rails/script/ready.sh',
        'args' => [],
        'timeout' => '10m'
      }

      navigator_hook = {
        'command' => '/rails/script/hook_navigator_idle.sh',
        'args' => [],
        'timeout' => '5m'
      }

      hooks['server']['idle'] << navigator_hook
      hooks['server']['stop'] << navigator_hook

      hooks['tenant']['stop'] << {
        'command' => '/rails/script/hook_app_idle.sh',
        'args' => [],
        'timeout' => '2m'
      }
    elsif ENV['KAMAL_CONTAINER_NAME']
      hooks['server']['start'] << {
        'command' => '/rails/script/hook_navigator_start.sh',
        'args' => [],
        'timeout' => '10s'
      }

      hooks['server']['start'] << {
        'command' => '/rails/script/update_htpasswd.rb',
        'args' => [],
        'timeout' => '30s'
      }

      hooks['server']['ready'] << {
        'command' => '/rails/script/ready.sh',
        'args' => [],
        'timeout' => '10m'
      }
    end

    hooks
  end

  def write_yaml_if_changed(file_path, data)
    require 'yaml'
    output = YAML.dump(data)
    existing_content = File.read(file_path) rescue nil

    unless existing_content == output
      File.write(file_path, output)
      true
    else
      false
    end
  end
end
