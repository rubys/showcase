# RegionConfiguration will be autoloaded by Rails since we added lib to autoload_paths
require 'set'

module Configurator
  DBPATH = ENV['RAILS_DB_VOLUME'] || Rails.root.join('db').to_s

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

  private

  # Cache showcases.yml to avoid repeated file reads
  def showcases
    @showcases ||= YAML.load_file(File.join(Rails.root, 'config/tenant/showcases.yml'))
  end

  def build_navigator_config
    config = {
      'server' => build_server_config,
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

  def build_server_config
    host = determine_host
    root = determine_root_path

    config = {
      'listen' => determine_listen_port,
      'hostname' => host,
      'root_path' => root,
      'static' => {
        'public_dir' => Rails.root.join('public').to_s,
        'allowed_extensions' => %w[html htm txt xml json css js png jpg gif pdf xlsx],
        'try_files' => %w[index.html .html .htm .txt .xml .json],
        'cache_control' => build_cache_control(root)
      }
    }

    # Add idle configuration for Fly.io deployments
    if ENV['FLY_REGION']
      config['idle'] = {
        'action' => 'suspend',
        'timeout' => '15m'
      }
    end

    config
  end

  def build_auth_config
    htpasswd_path = File.join(DBPATH, 'htpasswd')
    root = determine_root_path

    # Only return auth config if htpasswd file exists
    return nil unless File.exist?(htpasswd_path)

    public_paths = [
      "#{root}/assets/",
      "#{root}/cable",
      "#{root}/docs/",
      "#{root}/events/console",
      "#{root}/password/",
      "#{root}/regions/",
      "#{root}/studios/",
      "#{root}/favicon.ico",
      "#{root}/robots.txt",
      "#{root}/index_update",
      "#{root}/index_date",
      '*.css',
      '*.js',
      '*.png',
      '*.jpg',
      '*.gif'
    ]

    if ENV['FLY_REGION']
      public_paths << "#{root}/showcase/regions/#{ENV['FLY_REGION']}/cable"
      public_paths << "#{root}/regions/#{ENV['FLY_REGION']}/demo/"
    end

    # Add year paths to public_paths for public static showcase pages
    showcases.keys.each do |year|
      public_paths << "#{root}/#{year}/"
    end

    {
      'enabled' => true,
      'realm' => 'Showcase',
      'htpasswd' => htpasswd_path,
      'public_paths' => public_paths
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

    # Add WebSocket proxy for Action Cable
    # For FLY_REGION: /showcase/regions/iad/cable -> proxy to :28080/cable
    # For local dev: /showcase/cable -> proxy to :28080/cable
    # For no root: /cable -> proxy to :28080/cable
    # Use regex capture groups to strip path prefix and proxy just /cable
    if ENV['FLY_REGION']
      cable_path = "^#{root}/regions/#{ENV['FLY_REGION']}(/cable)$"
      cable_target = 'http://localhost:28080$1'
    elsif !root.empty?
      cable_path = "^#{root}(/cable)$"
      cable_target = 'http://localhost:28080$1'
    else
      cable_path = "^/cable$"
      cable_target = 'http://localhost:28080/cable'
    end

    routes['reverse_proxies'] << {
      'path' => cable_path,
      'target' => cable_target,
      'websocket' => true,
      'headers' => {
        'X-Forwarded-For' => '$remote_addr',
        'X-Forwarded-Proto' => '$scheme',
        'X-Forwarded-Host' => '$host'
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
    if ENV['RAILS_PROXY_HOST'] != 'rubix.intertwingly.net'
      routes['reverse_proxies'] << {
        'path' => '^/showease/password',
        'target' => 'https://rubix.intertwingly.net/showcase/password',
        'headers' => {
          'X-Forwarded-Host' => '$host'
        }
      }

      routes['reverse_proxies'] << {
        'path' => '^/showcase/studios/([a-z]*)/request$',
        'target' => 'https://rubix.intertwingly.net/showcase/studios/$1/request',
        'headers' => {
          'X-Forwarded-Host' => '$host'
        }
      }
    end
    
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
    # Group sites and years by region (like nginx-config.rb does)
    regions = {}
    showcases.each do |year, sites|
      sites.each do |token, info|
        site_region = info[:region]
        next unless site_region && site_region != current_region
        
        regions[site_region] ||= { years: Set.new, sites: Set.new }
        regions[site_region][:years] << year
        regions[site_region][:sites] << token
      end
    end
    
    # Add region index fly-replay routes
    regions.keys.each do |target_region|
      routes['fly']['replay'] << {
        'path' => "#{root}/regions/#{target_region}/",
        'region' => target_region,
        'status' => 307
      }
    end

    # Add event-specific routing for each region using only years that actually exist in that region
    regions.each do |target_region, data|
      years = data[:years].to_a.sort.join('|')
      sites = data[:sites].to_a.sort.join('|')

      # Fly-replay for all methods - Navigator automatically falls back to reverse proxy
      # when content constraints prevent fly-replay (eliminating need for separate reverse proxy rules)
      routes['fly']['replay'] << {
        'path' => "^#{root}/(?:#{years})/(?:#{sites})(?:/.*)?$",
        'region' => target_region,
        'status' => 307
      }
    end
  end

  def build_applications_config
    tenants = build_tenants_list

    {
      'framework' => build_framework_config,
      'env' => build_application_env,
      'health_check' => '/up',
      'startup_timeout' => '5s',
      'track_websockets' => false,  # WebSockets proxied to standalone Action Cable server
      'tenants' => tenants,
      'pools' => build_pools_config
    }
  end

  def build_pools_config
    config = {
      'max_size' => calculate_pool_size,
      'timeout' => '5m',
      'start_port' => 4000
    }

    # Add memory limits and user/group isolation for Fly.io (Linux) deployments
    if ENV['FLY_REGION']
      config['default_memory_limit'] = '768M'
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
    env['RAILS_APP_REDIS'] = 'showcase_production'

    # Enable JSON logging for navigator-managed apps
    env['RAILS_LOG_JSON'] = 'true'

    # Action Cable configuration
    if ENV['FLY_REGION']
      env['RAILS_CABLE_PATH'] = "/showcase/regions/#{ENV['FLY_REGION']}/cable"
    else
      env['RAILS_CABLE_PATH'] = '/showcase/cable'
    end

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
      dbpath = ENV['RAILS_DB_VOLUME'] || Rails.root.join('db').to_s
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

            if info[:locale].present?
              tenant['env']['RAILS_LOCALE'] = info[:locale].gsub('-', '_')
            end

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

          if info[:locale].present?
            tenant['env']['RAILS_LOCALE'] = info[:locale].gsub('-', '_')
          end

          tenants << tenant
        end
      end
    end

    # Write out a list of database files for bin/prerender
    tenant_lists = File.open('tmp/tenants.list', 'w')
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
    if File.exist?(maps_file)
      map = YAML.load_file(maps_file).dig('regions', region, 'map') rescue 'us'
      (map || 'us') == 'us' ? 'letter' : 'a4'
    else
      'letter'
    end
  end

  def load_studios
    showcases.values.map(&:keys).flatten.uniq.sort
  end

  def build_managed_processes_config
    # Return an array of managed process configurations
    # This can be customized based on your needs
    processes = []
    
    # Add standalone Action Cable server
    processes << {
      'name' => 'action-cable',
      'command' => 'bundle',
      'args' => ['exec', 'puma', '-p', ENV.fetch('CABLE_PORT', '28080'), 'cable/config.ru'],
      'working_dir' => Rails.root.to_s,
      'env' => {
        'RAILS_ENV' => 'production',
        'RAILS_APP_REDIS' => 'showcase_production',  # Same channel prefix as Rails tenants
        'RAILS_APP_DB' => 'action-cable'  # Used for logging
      },
      'auto_restart' => true,
      'start_delay' => '1s'  # Wait 1 second after Navigator starts
    }
    
    # Add a Redis server if running on Fly.io
    if ENV['FLY_APP_NAME']
      processes << {
        'name' => 'redis',
        'command' => 'redis-server',
        'args' => ['/etc/redis/redis.conf'],
        'working_dir' => Rails.root.to_s,
        'env' => {},
        'auto_restart' => true,
        'start_delay' => '2s'
      }
    end
    
    processes
  end
  
  def build_hooks_config
    hooks = {
      'server' => {
        'start' => [],
        'stop' => [],
        'idle' => [],
        'resume' => []
      },
      'tenant' => {
        'start' => [],
        'stop' => []
      }
    }

    # Add idle and stop hooks if running on Fly.io
    if ENV['FLY_REGION']
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
end
