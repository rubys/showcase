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

  def build_navigator_config
    config = {
      'server' => build_server_config,
      'pools' => build_pools_config,
      'auth' => build_auth_config,
      'routes' => build_routes_config,
      'static' => build_static_config,
      'applications' => build_applications_config,
      'process' => build_process_config,
      'logging' => build_logging_config,
      'health' => build_health_config,
      'managed_processes' => build_managed_processes_config
    }
    
    # Add suspend configuration if running on Fly.io
    if ENV['FLY_REGION']
      config['suspend'] = build_suspend_config
    end
    
    config
  end

  def build_server_config
    host = determine_host
    {
      'listen' => determine_listen_port,
      'hostname' => host,
      'root_path' => determine_root_path,
      'public_dir' => Rails.root.join('public').to_s,
      'maintenance_page' => '/503.html'
    }
  end

  def build_pools_config
    mem = File.exist?('/proc/meminfo') ?
      IO.read('/proc/meminfo')[/\d+/].to_i : `sysctl -n hw.memsize`.to_i/1024
    pool_size = 6 + mem / 1024 / 1024
    
    {
      'max_size' => pool_size,
      'idle_timeout' => 300,
      'start_port' => 4000
    }
  end

  def build_auth_config
    htpasswd_path = File.join(DBPATH, 'htpasswd')
    studios = load_studios
    root = determine_root_path
    
    auth = {
      'enabled' => File.exist?(htpasswd_path),
      'realm' => 'Showcase',
      'htpasswd' => htpasswd_path,
      'public_paths' => [
        "#{root}/assets/",
        "#{root}/cable",
        "#{root}/docs/",
        "#{root}/password/",
        "#{root}/publish/",
        "#{root}/regions/",
        "#{root}/studios/",
        '*.css',
        '*.js',
        '*.png',
        '*.jpg',
        '*.gif'
      ]
    }
    
    # Add pattern-based exclusions
    auth['exclude_patterns'] = build_auth_exclusions(studios)
    
    auth
  end

  def build_auth_exclusions(studios)
    patterns = []
    root = determine_root_path
    
    # Add root showcase path
    patterns << {
      'pattern' => "^#{root}/?$",
      'description' => 'Root showcase path'
    }
    
    # Year-based index pages are now served as static files
    # No need for complex exclude patterns since Navigator's try_files
    # will automatically serve the pre-rendered HTML files
    
    # Add static file pattern
    patterns << {
      'pattern' => "^#{root}/[-\\w]+\\.\\w+$",
      'description' => 'Static files in root'
    }
    
    # Add public event pages
    patterns << {
      'pattern' => "^#{root}/\\d{4}/\\w+/([-\\w]+/)?public/",
      'description' => 'Public event pages'
    }
    
    # Add event console
    patterns << {
      'pattern' => "^#{root}/events/console$",
      'description' => 'Event console access'
    }
    
    # Add studio-specific patterns if needed
    if studios.any?
      patterns << {
        'pattern' => "^#{root}/studios/(#{studios.join('|')}|)$",
        'description' => 'Studio pages'
      }
    end
    
    patterns
  end

  def build_routes_config
    root = determine_root_path
    region = ENV['FLY_REGION']
    
    routes = {
      'redirects' => [],
      'rewrites' => [],
      'proxies' => [],
      'fly_replay' => [],
      'reverse_proxies' => []
    }
    
    # Add redirects
    if region
      routes['redirects'] << { 'from' => '^/$', 'to' => "#{root}/regions/" }
      routes['redirects'] << { 'from' => "^#{root}/demo$", 'to' => "#{root}/demo/" }
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
      routes['rewrites'] << { 'from' => '^/([^/]+\.(gif|png|jpg|jpeg|ico|pdf|svg|webp))$', 'to' => "#{root}/$1" }
    end
    
    # Add proxy routes for remote services
    if ENV['FLY_APP_NAME']
      routes['proxies'] << {
        'path' => '/password',
        'target' => 'https://rubix.intertwingly.net/showcase/password',
        'headers' => {
          'X-Forwarded-Host' => '$host'
        }
      }
      
      routes['proxies'] << {
        'path' => '^/studios/([a-z]*)/request$',
        'target' => 'https://rubix.intertwingly.net/showcase/studios/$1/request',
        'headers' => {
          'X-Forwarded-Host' => '$host'
        }
      }
    end
    
    # Add fly-replay and reverse proxy support for cross-region events
    if region && ENV['FLY_APP_NAME']
      add_cross_region_routing(routes, root, region)
    end
    
    routes
  end

  def add_cross_region_routing(routes, root, current_region)
    showcases = YAML.load_file(File.join(Rails.root, 'config/tenant/showcases.yml'))
    
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
      routes['fly_replay'] << {
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
      routes['fly_replay'] << {
        'path' => "^#{root}/(?<year>#{years})/(?<site>#{sites})(?<rest>/.*)?$",
        'region' => target_region,
        'status' => 307
      }
    end
  end

  def build_static_config
    root = determine_root_path
    directories = [
      { 'path' => "#{root}/assets/", 'root' => 'assets/', 'cache' => 86400 },
      { 'path' => "#{root}/docs/", 'root' => 'docs/' },
      { 'path' => "#{root}/fonts/", 'root' => 'fonts/' },
      { 'path' => "#{root}/regions/", 'root' => 'regions/' },
      { 'path' => "#{root}/studios/", 'root' => 'studios/' }
    ]
    
    # Add year-based directories (2022, 2023, 2024, 2025, etc.)
    showcases = YAML.load_file(File.join(Rails.root, 'config/tenant/showcases.yml'))
    showcases.keys.each do |year|
      directories << { 'path' => "#{root}/#{year}/", 'root' => "#{year}/" }
    end
    
    # Add root path for serving root-level static files (e.g., /arthur-murray-logo.gif)
    # This allows files directly in public/ to be served
    if root != ''
      directories << { 'path' => "#{root}/", 'root' => '.', 'cache' => 86400 }
    else
      directories << { 'path' => "/", 'root' => '.', 'cache' => 86400 }
    end
    
    {
      'directories' => directories,
      'extensions' => %w[html htm txt xml json css js png jpg gif pdf xlsx],
      'try_files' => {
        'enabled' => true,
        'suffixes' => %w[index.html .html .htm .txt .xml .json],
        'fallback' => 'rails'
      }
    }
  end

  def build_applications_config
    tenants = build_tenants_list
    
    {
      'global_env' => build_global_env,
      'standard_vars' => build_standard_vars,
      'tenants' => tenants
    }
  end

  def build_standard_vars
    storage = ENV['RAILS_STORAGE'] || Rails.root.join('storage').to_s
    dbpath = ENV['RAILS_DB_VOLUME'] || Rails.root.join('db').to_s
    {
      'RAILS_APP_DB' => '${tenant.database}',
      'RAILS_APP_OWNER' => '${tenant.owner}',
      'RAILS_STORAGE' => storage,
      'RAILS_APP_SCOPE' => '${tenant.scope}',
      'DATABASE_URL' => "sqlite3://#{dbpath}/${tenant.database}.sqlite3",
      'PIDFILE' => "#{Rails.root}/tmp/pids/${tenant.database}.pid"
    }
  end

  def build_tenants_list
    showcases = YAML.load_file(File.join(Rails.root, 'config/tenant/showcases.yml'))
    region = ENV['FLY_REGION']
    storage = ENV['RAILS_STORAGE'] || Rails.root.join('storage').to_s
    root = determine_root_path
    
    tenants = []
    
    # Add index tenant (special case - doesn't use standard_vars)
    tenants << {
      'name' => 'index',
      'path' => root.empty? ? '/' : "#{root}/",
      'group' => 'showcase-index',
      'special' => true,
      'env' => {
        'RAILS_APP_DB' => 'index',
        'RAILS_APP_OWNER' => 'Index',
        'RAILS_STORAGE' => File.join(storage, 'index'),
        'PIDFILE' => "#{Rails.root}/tmp/pids/index.pid",
        'RAILS_SERVE_STATIC_FILES' => 'true'
      }
    }
    
    # Add demo tenant if in a region
    if region || ENV['KAMAL_CONTAINER_NAME']
      dbpath = ENV['RAILS_DB_VOLUME'] || Rails.root.join('db').to_s
      tenants << {
        'name' => 'demo',
        'path' => region ? "/regions/#{region}/demo/" : "/demo/",
        'group' => 'showcase-demo',
        'database' => 'demo',
        'owner' => 'Demo',
        'storage' => '/demo/storage/demo',
        'scope' => region ? "regions/#{region}/demo" : "demo",
        'env' => {
          'SHOWCASE_LOGO' => 'intertwingly.png',
          'DATABASE_URL' => "sqlite3://#{dbpath}/demo.sqlite3"
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
              'name' => "#{year}-#{token}-#{subtoken}",
              'path' => "#{root}/#{year}/#{token}/#{subtoken}/",
              'group' => "showcase-#{year}-#{token}-#{subtoken}",
              'database' => "#{year}-#{token}-#{subtoken}",
              'owner' => info[:name],
              'scope' => "#{year}/#{token}/#{subtoken}",
              'env' => {
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
            'name' => "#{year}-#{token}",
            'path' => "#{root}/#{year}/#{token}/",
            'group' => "showcase-#{year}-#{token}",
            'database' => "#{year}-#{token}",
            'owner' => info[:name],
            'scope' => "#{year}/#{token}",
            'env' => {
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
    
    # Add cable tenant (special case - no standard vars)
    cable_config = {
      'name' => 'cable',
      'path' => "#{root}/cable",
      'group' => 'showcase-cable',
      'special' => true,
      'match_pattern' => '*/cable',  # Match any path ending in /cable
      'force_max_concurrent_requests' => 0
    }
    
    # If standalone cable is enabled, add standalone server configuration
    if ENV['START_CABLE'] == 'true'
      cable_config['standalone_server'] = "localhost:#{ENV.fetch('CABLE_PORT', '28080')}"
    end
    
    tenants << cable_config
    
    # Add publish tenant (special case - no standard vars)
    tenants << {
      'name' => 'publish',
      'path' => "#{root}/publish",
      'group' => 'showcase-publish',
      'special' => true,
      'root' => Rails.root.join('fly/applications/publish/public').to_s,
      'env' => {
        'SECRET_KEY_BASE' => '1'
      }
    }
    
    tenants
  end

  def build_global_env
    env = {}
    
    root = determine_root_path
    if root != ''
      env['RAILS_RELATIVE_URL_ROOT'] = root
    end
    
    env['RAILS_APP_REDIS'] = 'showcase_production'
    
    env
  end

  def build_process_config
    {
      'ruby' => RbConfig.ruby,
      'bundler_preload' => true,
      'min_instances' => 0
    }
  end

  def build_logging_config
    config = {
      'level' => 'info',
      'format' => 'combined'
    }
    
    if ENV['FLY_APP_NAME'] || ENV['KAMAL_CONTAINER_NAME']
      config['access_log'] = '/dev/stdout'
      config['error_log'] = '/dev/stderr'
    else
      config['access_log'] = Rails.root.join('log/access.log').to_s
      config['error_log'] = Rails.root.join('log/error.log').to_s
    end
    
    config
  end

  def build_health_config
    {
      'endpoint' => '/up',
      'timeout' => 5,
      'interval' => 30
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
    showcases = YAML.load_file(File.join(Rails.root, 'config/tenant/showcases.yml'))
    showcases.values.map(&:keys).flatten.uniq.sort
  end

  def build_managed_processes_config
    # Return an array of managed process configurations
    # This can be customized based on your needs
    processes = []
    
    # Add standalone Action Cable server if configured
    if ENV['START_CABLE'] == 'true'
      processes << {
        'name' => 'action-cable',
        'command' => 'bundle',
        'args' => ['exec', 'puma', '-p', ENV.fetch('CABLE_PORT', '28080'), 'cable/config.ru'],
        'working_dir' => Rails.root.to_s,
        'env' => {
          'RAILS_ENV' => Rails.env,
          'RAILS_MAX_THREADS' => '10'  # Handle multiple concurrent WebSocket connections
        },
        'auto_restart' => true,
        'start_delay' => 2  # Wait 2 seconds after Navigator starts
      }
    end
    
    # Example: Add a Redis server if configured
    if ENV['START_REDIS'] == 'true'
      processes << {
        'name' => 'redis',
        'command' => 'redis-server',
        'args' => [],
        'working_dir' => Rails.root.to_s,
        'env' => {},
        'auto_restart' => true,
        'start_delay' => 0
      }
    end
    
    # Example: Add a background worker if configured
    if ENV['START_WORKER'] == 'true'
      processes << {
        'name' => 'sidekiq',
        'command' => 'bundle',
        'args' => ['exec', 'sidekiq'],
        'working_dir' => Rails.root.to_s,
        'env' => {
          'RAILS_ENV' => Rails.env
        },
        'auto_restart' => true,
        'start_delay' => 4  # Wait for cable server to start first
      }
    end
    
    # Example: Add a custom monitoring script
    if ENV['START_MONITOR'] == 'true'
      processes << {
        'name' => 'monitor',
        'command' => Rails.root.join('bin', 'monitor').to_s,
        'args' => [],
        'working_dir' => Rails.root.to_s,
        'env' => {
          'RAILS_ENV' => Rails.env,
          'MONITOR_PORT' => '8080'
        },
        'auto_restart' => true,
        'start_delay' => 5  # Wait 5 seconds after Navigator starts
      }
    end
    
    # You can add more processes here as needed
    # They will be started when Navigator starts and stopped when it exits
    
    processes
  end
  
  def build_suspend_config
    {
      'enabled' => true,
      'idle_timeout' => 1200  # 20 minutes in seconds
    }
  end
end
