# RegionConfiguration will be autoloaded by Rails since we added lib to autoload_paths

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
    file = File.join(Rails.root, 'tmp', 'navigator.yaml')
    RegionConfiguration.write_yaml_if_changed(file, config)
  end

  private

  def build_navigator_config
    {
      'server' => build_server_config,
      'pools' => build_pools_config,
      'auth' => build_auth_config,
      'routes' => build_routes_config,
      'static' => build_static_config,
      'applications' => build_applications_config,
      'process' => build_process_config,
      'logging' => build_logging_config,
      'health' => build_health_config
    }
  end

  def build_server_config
    host = determine_host
    {
      'listen' => determine_listen_port,
      'hostname' => host,
      'root_path' => determine_root_path,
      'public_dir' => Rails.root.join('public').to_s
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
    
    # Add index pages for years/events
    patterns << {
      'pattern' => '^/\\d{4}/\\w+/?$',
      'description' => 'Event index pages'
    }
    
    # Add public event pages
    patterns << {
      'pattern' => '^/\\d{4}/\\w+/([-\\w]+/)?public/',
      'description' => 'Public event pages'
    }
    
    # Add event console
    patterns << {
      'pattern' => '^/events/console$',
      'description' => 'Event console access'
    }
    
    # Add studio-specific patterns if needed
    if studios.any?
      patterns << {
        'pattern' => "^/studios/(#{studios.join('|')}|)$",
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
      'proxies' => []
    }
    
    # Add redirects
    if region
      routes['redirects'] << { 'from' => '^/$', 'to' => "#{root}/regions/" }
      routes['redirects'] << { 'from' => "^#{root}/demo$", 'to' => "#{root}/demo/" }
    elsif root != ''
      routes['redirects'] << { 'from' => '^/(showcase)?$', 'to' => "#{root}/" }
    else
      routes['redirects'] << { 'from' => '^/$', 'to' => "#{root}/studios/" }
    end
    
    # Add rewrites
    if root != ''
      routes['rewrites'] << { 'from' => '^/assets/(.*)', 'to' => "#{root}/assets/$1" }
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
    
    routes
  end

  def build_static_config
    root = determine_root_path
    {
      'directories' => [
        { 'path' => "#{root}/assets/", 'root' => 'assets/', 'cache' => 86400 },
        { 'path' => "#{root}/docs/", 'root' => 'docs/' },
        { 'path' => "#{root}/fonts/", 'root' => 'fonts/' },
        { 'path' => "#{root}/regions/", 'root' => 'regions/' },
        { 'path' => "#{root}/studios/", 'root' => 'studios/' }
      ],
      'extensions' => %w[html htm txt xml json css js png jpg gif pdf xlsx],
      'try_files' => {
        'enabled' => true,
        'suffixes' => %w[.html .htm .txt .xml .json],
        'fallback' => 'rails'
      }
    }
  end

  def build_applications_config
    tenants = build_tenants_list
    
    {
      'global_env' => build_global_env,
      'tenants' => tenants
    }
  end

  def build_tenants_list
    showcases = YAML.load_file(File.join(Rails.root, 'config/tenant/showcases.yml'))
    region = ENV['FLY_REGION']
    storage = ENV['RAILS_STORAGE'] || Rails.root.join('storage').to_s
    
    tenants = []
    
    # Add index tenant
    tenants << {
      'name' => 'index',
      'path' => '/',
      'group' => 'showcase-index',
      'database' => 'index',
      'env' => {
        'RAILS_SERVE_STATIC_FILES' => 'true'
      }
    }
    
    # Add demo tenant if in a region
    if region || ENV['KAMAL_CONTAINER_NAME']
      tenants << {
        'name' => 'demo',
        'path' => region ? "/regions/#{region}/demo/" : "/demo/",
        'group' => 'showcase-demo',
        'database' => 'demo',
        'storage' => '/demo/storage/demo',
        'env' => {
          'SHOWCASE_LOGO' => 'intertwingly.png'
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
              'path' => "/#{year}/#{token}/#{subtoken}/",
              'group' => "showcase-#{year}-#{token}-#{subtoken}",
              'database' => "#{year}-#{token}-#{subtoken}",
              'owner' => "#{info[:name]} - #{subinfo[:name]}",
              'storage' => File.join(storage, "#{year}-#{token}-#{subtoken}"),
              'env' => {
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
            'name' => "#{year}-#{token}",
            'path' => "/#{year}/#{token}/",
            'group' => "showcase-#{year}-#{token}",
            'database' => "#{year}-#{token}",
            'owner' => info[:name],
            'storage' => File.join(storage, "#{year}-#{token}"),
            'env' => {
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
    
    # Add cable tenant
    tenants << {
      'name' => 'cable',
      'path' => '/cable',
      'group' => 'showcase-cable',
      'database' => nil,
      'force_max_concurrent_requests' => 0
    }
    
    # Add publish tenant
    tenants << {
      'name' => 'publish',
      'path' => '/publish',
      'group' => 'showcase-publish',
      'database' => nil,
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
    
    if ENV['RAILS_LOG_VOLUME']
      env['RAILS_LOG_VOLUME'] = ENV['RAILS_LOG_VOLUME']
    end
    
    if ENV['RAILS_DB_VOLUME']
      env['RAILS_DB_VOLUME'] = ENV['RAILS_DB_VOLUME']
    end
    
    if ENV['GEM_HOME']
      env['GEM_HOME'] = ENV['GEM_HOME']
    end
    
    if ENV['GEM_PATH']
      env['GEM_PATH'] = ENV['GEM_PATH']
    end
    
    if ENV['FLY_REGION']
      env['PAPERSIZE'] = determine_papersize
    end
    
    unless ENV['FLY_REGION']
      env['RAILS_PROXY_HOST'] = determine_host
    end
    
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
end
