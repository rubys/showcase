#!/usr/bin/env ruby

require 'erb'
require 'yaml'
require 'ostruct'

HOST = 'rubix.intertwingly.net'
ROOT = '/showcase'

if File.exist? '/opt/homebrew/etc/nginx'
  NGINX_CONF = '/opt/homebrew/etc/nginx/servers'
elsif File.exist? '/etc/nginx/sites-enabled'
  NGINX_CONF = '/etc/nginx/sites-enabled'
end

SHOWCASE_CONF = "#{NGINX_CONF}/showcase.conf"

@git_path = File.realpath(File.expand_path('../..', __dir__))

showcases = YAML.load_file("#{__dir__}/showcases.yml")
template = ERB.new(DATA.read)

restart = (not ARGV.include?('--restart'))

Dir.chdir @git_path

index = OpenStruct.new(
  name:  "index",
  label: "index",
  scope: "__index__",
)

ENV['RAILS_APP_DB'] = index.label
system 'bin/rails db:create' unless File.exist? "db/#{index.label}.sqlite3"

@tenants = [index]
showcases.each do |year, list|
  list.each do |token, info|
    @tenants << OpenStruct.new(
      name:  info[:name],
      label: "#{year}-#{token}",
      scope: "#{year}/#{token}"
    )
  end
end

@tenants.each do |tenant|
  ENV['RAILS_APP_DB'] = tenant.label
  system 'bin/rails db:create' unless File.exist? "db/#{tenant.label}.sqlite3"
  system 'bin/rails db:migrate'

  count = `sqlite3 db/#{tenant.label}.sqlite3 "select count(*) from events"`.to_i
  system 'bin/rails db:seed' if count == 0
end

old_conf = IO.read(SHOWCASE_CONF) rescue nil
new_conf = template.result(binding)

if new_conf != old_conf
  STDERR.puts SHOWCASE_CONF
  IO.write SHOWCASE_CONF, new_conf
  restart = true
end

system 'nginx -s reload' if restart

__END__
server {
  listen 9999;
  server_name localhost;

  # Tell Nginx and Passenger where your app's 'public' directory is
  root <%= @git_path %>/public;
  passenger_enabled on;
  passenger_ruby <%= RbConfig.ruby %>;
  passenger_friendly_error_pages on;
  passenger_min_instances 0;
  passenger_env_var RAILS_RELATIVE_URL_ROOT <%= ROOT %>;
  passenger_env_var RAILS_PROXY_HOST https://rubix.intertwingly.net/;
  passenger_env_var RAILS_APP_REDIS showcase_production;
  passenger_env_var RAILS_APP_CABLE wss://rubix.intertwingly.net<%= ROOT %>/cable;

  location /showcase {
    alias <%= @git_path %>/public;
    try_files $uri @index;
  }
 
  location @index {
    rewrite ^/showcase/(.*)$ /showcase/__index__/$1;
  }

  location <%= ROOT %>/cable {
    passenger_app_group_name showcase-cable;
    passenger_force_max_concurrent_requests_per_process 0;
  }
  <% @tenants.each do |tenant| %>
  # <%= tenant.name %>
  location <%= ROOT %>/<%= tenant.scope %> {
    passenger_app_group_name showcase-<%= tenant.label %>;
    passenger_env_var RAILS_APP_DB <%= tenant.label %>;
    passenger_env_var RAILS_APP_SCOPE <%= tenant.scope %>;
    passenger_env_var PIDFILE <%= @git_path %>/tmp/pids/<%= tenant.label %>.pid;
  }
  <% end %>
}
