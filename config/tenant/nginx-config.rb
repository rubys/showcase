#!/usr/bin/env ruby

require 'erb'
require 'yaml'
require 'fileutils'
require 'ostruct'

ROOT = '/showcase'

HOST = if ENV['FLY_APP_NAME']
   "#{ENV['FLY_APP_NAME']}.fly.dev"
elsif `hostname` =~ /^ubuntu/
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
showcases.each do |year, list|
  list.each do |token, info|
    if info[:events]
      info[:events].each do |subtoken, subinfo|
        @tenants << OpenStruct.new(
          owner:  info[:name],
          region: info[:region],
          name:   info[:name] + ' - ' + subinfo[:name] ,
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

@dbpath = ENV.fetch('RAILS_DB_VOLUME') { "#{@git_path}/db" }
FileUtils.mkdir_p @dbpath
@tenants.each do |tenant|
  next if @region and tenant.region and @region != tenant.region
  ENV['RAILS_APP_DB'] = tenant.label
  ENV['DATABASE_URL'] = "sqlite3://#{@dbpath}/#{tenant.label}.sqlite3"
  system 'bin/rails db:prepare'

  count = `sqlite3 #{@dbpath}/#{tenant.label}.sqlite3 "select count(*) from events"`.to_i
  system 'bin/rails db:seed' if count == 0

  storage = File.join(@storage, tenant.label)
  FileUtils.mkdir_p storage unless Dir.exist? storage
end

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

__END__
<% if @region -%>
passenger_default_user root;
passenger_default_group root;

passenger_log_file /dev/stdout;

passenger_ctl hook_detached_process /rails/bin/passenger-hook;

<% end -%>
server {
<% if ENV['FLY_APP_NAME'] -%>
  listen 3000;
  server_name <%= ENV['FLY_APP_NAME'] %>.fly.dev;
<% else -%>
  listen 9999;
  server_name localhost;
<% end -%>
  port_in_redirect off;
  rewrite ^/(showcase)?$ /showcase/ redirect;
  rewrite ^/assets/ /showcase/assets/ last;

  # Authentication
<% if File.exist? "#{@dbpath}/htpasswd" -%>
  satisfy any;
  allow 127.0.0.1;
  allow ::1;

  set $realm "Showcase";
  if ($request_uri ~ "^/showcase/(assets/|cable$|docs/|password/|publish/|$)") { set $realm off; }
  <%- if @region -%>
  if ($request_uri ~ "^/showcase/<%= @cables %>/cable$") { set $realm off; }
  <%- end -%>
  if ($request_uri ~ "^/showcase/[-\w]+\.\w+$") { set $realm off; }
  if ($request_uri ~ "^/showcase/\d+/\w+/(\w+/)?public/") { set $realm off; }
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
  passenger_set_header X-Request-Id $request_id;
<% if ENV['GEM_HOME'] -%>
  passenger_env_var GEM_HOME <%= ENV['GEM_HOME'] %>;
<% end -%>
<% if ENV['GEM_PATH'] -%>
  passenger_env_var GEM_PATH <%= ENV['GEM_PATH'] %>;
<% end -%>
  passenger_env_var RAILS_RELATIVE_URL_ROOT <%= ROOT %>;
<% unless @region -%>
  passenger_env_var RAILS_PROXY_HOST <%= HOST %>;
<% end -%>
  passenger_env_var RAILS_APP_REDIS showcase_production;
<% @tenants.each do |tenant| %>
  # <%= tenant.name %>
<% if @region and @region == tenant.region and tenant.scope.to_s != '' -%>
  rewrite <%= ROOT %>/<%= tenant.scope %>/cable <%= ROOT %>/cable last;
<% end -%>
  location <%= ROOT %>/<%= tenant.scope %> {
<% if @region and tenant.region and @region != tenant.region -%>
    return 409 "wrong region\n";
    add_header Fly-Replay region=<%= tenant.region %> always;
<% else -%>
    root <%= @git_path %>/public;
    passenger_app_group_name showcase-<%= tenant.label %>;
    passenger_env_var RAILS_APP_OWNER <%= tenant.owner.inspect %>;
<% if ENV['RAILS_DB_VOLUME'] -%>
    passenger_env_var DATABASE_URL sqlite3://<%= "#{ENV['RAILS_DB_VOLUME']}/#{tenant.label}.sqlite3" %>;
    passenger_env_var RAILS_DB_VOLUME <%= ENV['RAILS_DB_VOLUME'] %>;
<% end -%>
    passenger_env_var RAILS_STORAGE <%= File.join(@storage, tenant.label) %>;
    passenger_env_var RAILS_APP_DB <%= tenant.label %>;
<% if tenant.label == 'index' -%>
    passenger_env_var RAILS_SERVE_STATIC_FILES true;
    passenger_base_uri /;
<% else -%>
    passenger_env_var RAILS_APP_SCOPE <%= tenant.scope %>;
<% if tenant.logo -%>
    passenger_env_var SHOWCASE_LOGO <%= tenant.logo %>;
<% end -%>
<% end -%>
    passenger_env_var PIDFILE <%= @git_path %>/tmp/pids/<%= tenant.label %>.pid;
<% end -%>
  }
<% end %>
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
