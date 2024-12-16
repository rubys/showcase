#!/usr/bin/env ruby

require 'erb'
require 'set'
require 'yaml'
require 'fileutils'
require 'ostruct'
require 'json'

HOST = if ENV['FLY_APP_NAME']
  "#{ENV['FLY_APP_NAME']}.fly.dev"
elsif `hostname` =~ /^ubuntu/ || ENV['KAMAL_CONTAINER_NAME']
  'hetzner.intertwingly.net'
else
  'rubix.intertwingly.net'
end

if File.exist? '/opt/homebrew/etc/nginx'
  NGINX_CONF = '/opt/homebrew/etc/nginx/servers'
elsif File.exist? '/etc/nginx/sites-enabled'
  NGINX_CONF = '/etc/nginx/sites-enabled'
end

SHOWCASE_CONF = "#{NGINX_CONF}/showcase.conf"

@git_path = File.realpath(File.expand_path('../..', __dir__))
@storage = ENV['RAILS_STORAGE'] || File.join(@git_path, 'storage')

showcases = YAML.load_file("#{__dir__}/showcases.yml")

restart = ARGV.include?('--restart')

Dir.chdir @git_path

index = OpenStruct.new(
  owner: 'index',
  name:  "index",
  label: "index",
  scope: "",
)

@tenants = [index]
@studios = showcases.values.map(&:keys).flatten.uniq.sort
@regions = Set.new
showcases.each do |year, list|
  list.each do |token, info|
    @regions << info[:region]

    if info[:events]
      info[:events].each do |subtoken, subinfo|
        @tenants << OpenStruct.new(
          owner:  info[:name],
          region: info[:region],
          name:   info[:name] + ' - ' + subinfo[:name] ,
          base:   "#{year}-#{token}",
          label:  "#{year}-#{token}-#{subtoken}",
          scope:  "#{year}/#{token}/#{subtoken}",
          logo:   info[:logo],
        )
      end
    else
      @tenants << OpenStruct.new(
        owner:  info[:name],
        region: info[:region],
        name:   info[:name],
        label:  "#{year}-#{token}",
        scope:  "#{year}/#{token}",
        logo:   info[:logo],
      )
    end
  end
end

@region = ENV['FLY_REGION']
REGIONS = @region ? `dig +short txt regions.smooth.internal`.scan(/\w+/) : []

ROOT = ENV['KAMAL_CONTAINER_NAME'] ? '' : '/showcase'

if @region
  regions = {}

  showcases.each do |year, sites|
    sites.each do |site, events|
      next unless events[:region]
      regions[events[:region]] ||= {years: Set.new, sites: Set.new}
      regions[events[:region]][:years] << year
      regions[events[:region]][:sites] << site
    end
  end

  # warn if there are regions in the configuration that are not on the network
  missing = @regions - REGIONS - [@region]
  unless missing.empty?
    STDERR.puts "Missing regions: #{missing.join(', ')}"
  end

  # add demo tenant
  @tenants << OpenStruct.new(
    owner:  'Demo',
    region: @region,
    name:   'demo',
    label:  "demo",
    scope:  "regions/#{@region}/demo",
    logo:   "intertwingly.png",
  )

  FileUtils.mkdir_p "/demo/db"
  FileUtils.mkdir_p "/demo/storage/demo"

  # install prebuilt demo database
  if File.exist?("/rails/db/demo.sqlite3") && !File.exist?("/demo/db/demo.sqlite3")
    FileUtils.cp "/rails/db/demo.sqlite3", "/demo/db/demo.sqlite3"
  end

  FileUtils.chown_R 'rails', 'rails', "/demo"
  FileUtils.rm_f "/demo/db/index.sqlite3"
  File.symlink "/data/db/index.sqlite3", "/demo/db/index.sqlite3"
end

years = showcases.select {|year, sites| sites.any? {|name, site| site[:region] == @region}}.
  map do |year, sites|
    sites.select! {|name, site| site[:region] == @region}
    sites = sites.map do |name, site|
      if site[:events]
        name + '/(' + site[:events].keys.join('|') + ')'
      else
        name
      end
    end

    if sites.length == 1
      year.to_s + '/' + sites.first
    else
      year.to_s + '/(' + sites.join('|') + ')'
    end
  end

if years.length == 1
  @cables = years.first
else
  @cables = '(' + years.join('|') + ')'
end

years = years.map! do |year|
  multis = year.scan(/\w+\/\(.*?\)/)

  if multis.length == 0
    "#{year}"
  else
    "#{year}/(#{multis.join("|")})?"
  end
end

years = showcases.map do |year, sites|
  sites = sites.map do |name, site|
    name + '/' if site[:events]
  end.compact

  if sites.length == 0
    year
  else
    "#{year}(/(#{sites.join("|")}))?"
  end
end

if years.length == 1
  @indexes = years.first
else
  @indexes = '(' + years.join('|') + ')'
end

log_volume = ENV['RAILS_LOG_VOLUME']
FileUtils.mkdir_p log_volume if log_volume

@dbpath = ENV.fetch('RAILS_DB_VOLUME') { "#{@git_path}/db" }
FileUtils.mkdir_p @dbpath

mem = File.exist?('/proc/meminfo') ?
   IO.read('/proc/meminfo')[/\d+/].to_i : `sysctl -n hw.memsize`.to_i/1024
pool_size = 6 + mem / 1024 / 1024

old_conf = IO.read(SHOWCASE_CONF) rescue ''
new_conf = ERB.new(DATA.read, trim_mode: '-').result(binding)

if new_conf != old_conf
  IO.write SHOWCASE_CONF, new_conf
  restart = true
end

if restart
  if old_conf.include? @git_path
    system "passenger-config restart-app #{@git_path}"
  end

  pids = %w{/run/nginx.pid /run/nginx/nginx.pid /opt/homebrew/var/run/nginx.pid}
  if pids.any? {|file| File.exist? file}
    system 'nginx -s reload'
  end
end

migrations = Dir["#{@git_path}/db/migrate/2*"].map {|name| name[/\d+/]}

@tenants.each do |tenant|
  next if @region and tenant.region and @region != tenant.region
  ENV['RAILS_APP_DB'] = tenant.label
  database = "#{@dbpath}/#{tenant.label}.sqlite3"
  database = "/demo/db/#{tenant.label}.sqlite3" if tenant.owner == "Demo"

  # rename the database if it is not a symlink and there is a base
  if tenant.base and not File.exist?(database)
    basedb = "#{@dbpath}/#{tenant.base}.sqlite3"
    if File.exist?(basedb) and not File.symlink?(basedb)
      File.rename basedb, database
      Dir.chdir @dbpath do
        File.symlink File.basename(database), File.basename(basedb)
        FileUtils.chown_R 'rails', 'rails', File.basename(basedb)
      end
    end
  end

  if @region
    applied = []
    if File.exist?(database) and File.size(database) > 0
      begin
        applied = JSON.parse(`sqlite3 #{database} "select version from schema_migrations" --json`).map(&:values).flatten
      rescue
      end
    end

    unless (migrations - applied).empty?
      # only run migrations in one place - fly.io; rely on rsync to update others
      ENV['DATABASE_URL'] = "sqlite3://#{database}"
      system 'bin/rails db:prepare'

      # not sure why this is needed...
      count = `sqlite3 #{database} "select count(*) from events"`.to_i
      system 'bin/rails db:seed' if count == 0

      FileUtils.chown_R 'rails', 'rails', database
    end

    if tenant.owner == "Demo"
      FileUtils.cp database, "#{database}.seed", preserve: true
    end
  end

  storage = File.join(@storage, tenant.label)
  if not Dir.exist?(storage)
    basestore = File.join(@storage, tenant.base) if tenant.base
    if basestore and File.exist?(basestore) and not File.symlink?(basestore)
      File.rename basestore, storage
      Dir.chdir @storage do
        File.symlink File.basename(storage), File.basename(basestore)
        FileUtils.chown_R 'rails', 'rails', File.basename(basestore)
      end
    else
      unless Dir.exist? storage
        FileUtils.mkdir_p storage
        FileUtils.chown_R 'rails', 'rails', storage
      end
    end
  end
end

__END__
<% if @region -%>
passenger_default_user root;
passenger_default_group root;

passenger_log_file /dev/stdout;

passenger_pool_idle_time 300;
passenger_ctl hook_detached_process /rails/bin/passenger-hook;

resolver [fdaa::3]:53 valid=1s;

<% elsif ENV['KAMAL_CONTAINER_NAME'] -%>
passenger_default_user root;
passenger_default_group root;

passenger_log_file /dev/stdout;
<% end -%>
<% if ENV['FLY_APP_NAME'] || ENV['KAMAL_CONTAINER_NAME'] -%>
# logging
log_format  main  '$http_x_forwarded_for - $remote_user [$time_local] "$request" '
  '$status $body_bytes_sent [$request_id] $request_time "$http_referer" '
  '"$http_user_agent" - $http_fly_request_id';
map $request_uri $loggable {
  /up  0;
  default 1;
}
error_log /dev/stderr;
access_log /dev/stdout main if=$loggable;

<% end -%>
passenger_max_pool_size <%= pool_size %>;

server {
<% if ENV['FLY_APP_NAME'] -%>
  listen 3000;
  listen [::]:3000;
  server_name showcase.party;

  location ~ ^/showcase/(.*)$ {
    return 307 https://smooth.fly.dev/showcase/$1;
  }

  location ~ ^/(.*)$ {
    return 307 https://smooth.fly.dev/showcase/$1;
  }
}

server {
  listen 3000;
  listen [::]:3000;
  server_name <%= ENV['FLY_APP_NAME'] %>.fly.dev;
<% elsif ENV['KAMAL_CONTAINER_NAME'] -%>
  listen 3000;
  listen [::]:3000;
  server_name showcase.party;
<% else -%>
  listen 9999;
  server_name localhost;
<% end -%>
  port_in_redirect off;
<% if ENV['FLY_REGION'] -%>
  rewrite ^/$ <%= ROOT %>/regions/ redirect;
  rewrite ^<%= ROOT %>(/studios/?)?$ <%= ROOT %>/ redirect;
  rewrite ^<%= ROOT %>/demo$ <%= ROOT %>/demo/ redirect;
<% elsif ROOT != "" -%>
  rewrite ^/(showcase)?$ <%= ROOT %>/ redirect;
<% else -%>
  rewrite ^/$ <%= ROOT %>/studios/ redirect;
<% end -%>
<% if ROOT != "" -%>
  rewrite ^/assets/ <%= ROOT %>/assets/ last;
<% end -%>

  # Authentication
<% if File.exist? "#{@dbpath}/htpasswd" -%>
  satisfy any;
  allow 127.0.0.1;
  allow ::1;

  set $realm "Showcase";
  if ($request_uri ~ "^<%= ROOT %>/(assets/|cable$|docs/|password/|publish/|regions/((<%= @regions.join('|') %>)(/demo/.*)?)?$|studios/(<%= @studios.join('|') %>|)$|$)") { set $realm off; }
  <%- if @region -%>
  if ($request_uri ~ "^<%= ROOT %>/<%= @cables %>/cable$") { set $realm off; }
  <%- end -%>
  if ($request_uri ~ "^<%= ROOT %>/<%= @indexes %>/?$") { set $realm off; }
  if ($request_uri ~ "^<%= ROOT %>/[-\w]+\.\w+$") { set $realm off; }
  if ($request_uri ~ "^<%= ROOT %>/\d+/\w+/([-\w]+/)?public/") { set $realm off; }
  if ($request_uri ~ "^<%= ROOT %>/events/console$") { set $realm off; }
  auth_basic $realm;
  auth_basic_user_file <%= @dbpath %>/htpasswd;
<% else -%>
  auth_basic off;
<% end -%>

  # Configuration common to all apps
  client_max_body_size 1G;
  passenger_enabled on;
  passenger_ruby <%= RbConfig.ruby %>;
  passenger_friendly_error_pages on;
  passenger_min_instances 0;
  passenger_preload_bundler on;
  passenger_set_header X-Request-Id $request_id;
<% if ENV['GEM_HOME'] -%>
  passenger_env_var GEM_HOME <%= ENV['GEM_HOME'] %>;
<% end -%>
<% if ENV['GEM_PATH'] -%>
  passenger_env_var GEM_PATH <%= ENV['GEM_PATH'] %>;
<% end -%>
<% if ROOT != "" -%>
  passenger_env_var RAILS_RELATIVE_URL_ROOT <%= ROOT %>;
<% end -%>
<% if ENV['RAILS_LOG_VOLUME'] -%>
  passenger_env_var RAILS_LOG_VOLUME <%= ENV['RAILS_LOG_VOLUME'] %>;
<% end -%>
<% unless @region -%>
  passenger_env_var RAILS_PROXY_HOST <%= HOST %>;
<% end -%>
  passenger_env_var RAILS_APP_REDIS showcase_production;
<% if ENV['FLY_REGION'] -%>

  # Password reset
  location <%= ROOT %>/password {
    proxy_set_header Host $http_host;
    proxy_set_header X-Forwarded-Host $host;
    proxy_pass https://rubix.intertwingly.net/showcase/password;
  }

  # Demo
  location = <%= ROOT %>/demo/ {
    return 302 <%= ROOT %>/regions/<%= @region %>/demo/;
  }

  # PDF generation
  location ~ <%= ROOT %>/.+\.pdf$ {
    add_header Fly-Replay app=smooth-pdf;
    return 307;
  }

  # XLSX generation
  location ~ <%= ROOT %>/.+\.xlsx$ {
    add_header Fly-Replay app=smooth-pdf;
    return 307;
  }
<% elsif ENV['KAMAL_CONTAINER_NAME'] -%>

  # Health check
  location /up {
    default_type text/html;
    return 200 "OK";
  }
<% end %>
<% @tenants.each do |tenant| -%>
<% next if @region and tenant.region and @region != tenant.region -%>
  # <%= tenant.name %>
<% if @region and @region == tenant.region and tenant.scope.to_s != '' -%>
  rewrite <%= ROOT %>/<%= tenant.scope %>/cable <%= ROOT %>/cable last;
<% end -%>
<% if @region and tenant.region and @region != tenant.region -%>
  location <%= ROOT %>/<%= tenant.scope %>/cable {
    add_header Fly-Replay region=<%= tenant.region %>;
    return 307;
  }
  location <%= ROOT %>/<%= tenant.scope %> {
    proxy_set_header X-Forwarded-Host $host;
    proxy_pass http://<%= tenant.region %>.<%= ENV['FLY_APP_NAME'] %>.internal:3000<%= ROOT %>/<%= tenant.scope %>;
<% else -%>
  location <%= ROOT %>/<%= tenant.scope %> {
    root <%= @git_path %>/public;
    passenger_app_group_name showcase-<%= tenant.label %>;
    passenger_env_var RAILS_APP_OWNER <%= tenant.owner.inspect %>;
<% if tenant.owner == "Demo" &&  ENV['RAILS_DB_VOLUME'] -%>
    passenger_env_var DATABASE_URL sqlite3:///demo/db/<%= tenant.label %>.sqlite3;
    passenger_env_var RAILS_DB_VOLUME /demo/db;
    passenger_env_var RAILS_STORAGE <%= File.join('/demo/storage', tenant.label) %>;
<% else -%>
<% if ENV['RAILS_DB_VOLUME'] -%>
    passenger_env_var DATABASE_URL sqlite3://<%= "#{ENV['RAILS_DB_VOLUME']}/#{tenant.label}.sqlite3" %>;
    passenger_env_var RAILS_DB_VOLUME <%= ENV['RAILS_DB_VOLUME'] %>;
<% end -%>
    passenger_env_var RAILS_STORAGE <%= File.join(@storage, tenant.label) %>;
<% end -%>
    passenger_env_var RAILS_APP_DB <%= tenant.label %>;
<% if tenant.label == 'index' -%>
    passenger_env_var RAILS_SERVE_STATIC_FILES true;
    passenger_base_uri /;
<% else -%>
    passenger_env_var RAILS_APP_SCOPE <%= tenant.scope %>;
<% if tenant.logo -%>
    passenger_env_var SHOWCASE_LOGO <%= tenant.logo == '' ? "arthur-murray-logo.gif" : tenant.logo %>;
<% end -%>
<% end -%>
    passenger_env_var PIDFILE <%= @git_path %>/tmp/pids/<%= tenant.label %>.pid;
<% end -%>
  }

<% end -%>
<% if ENV['FLY_REGION'] -%>
<% @regions.to_a.sort.each do |region| -%>
  # <%= region %> region
<% if region == ENV['FLY_REGION'] -%>
  location <%= ROOT %>/regions/<%= region %>/logs/ {
    types {
      text/plain log;
    }

    autoindex on;
    alias /data/log/;
  }
<% else -%>
  location <%= ROOT %>/regions/<%= region %>/ {
    add_header Fly-Replay region=<%= region %>;
    return 307;
  }
<%
  data = regions[region]
  years = "(?<year>#{data[:years].to_a.sort.join('|')})"
  sites = "(?<site>#{data[:sites].to_a.sort.join('|')})"
%>
  location ~ <%= ROOT %>/<%= years %>/<%= sites %>(?<rest>/.*)?$ {
    if ($request_method = 'GET') {
      add_header Fly-Replay region=<%= region %>;
      return 307;
    }

    proxy_set_header X-Forwarded-Host $host;
<% if REGIONS.include?(region) -%>
    proxy_pass http://<%= region %>.smooth.internal:3000/showcase/$year/$site$rest;
<% else -%>
    return 410;
<% end -%>
  }
<% end -%>

<% end -%>
<% end -%>
  # Action cable (shared by all apps on this server listen port)
  location <%= ROOT %>/cable {
    root <%= @git_path %>/public;
    passenger_app_group_name showcase-cable;
    passenger_force_max_concurrent_requests_per_process 0;
  }

  # publish
  location <%= ROOT %>/publish {
    root <%= @git_path %>/fly/applications/publish/public;
    passenger_app_group_name showcase-publish;
    passenger_env_var SECRET_KEY_BASE 1;
  }
}
