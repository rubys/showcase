require 'erb'
require 'yaml'
require 'ostruct'

HOST = 'rubix.intertwingly.net'
ROOT = '/showcase'

NGINX_SERVERS = "/opt/homebrew/etc/nginx/servers"
SHOWCASE_CONF = "#{NGINX_SERVERS}/showcase.conf"

@git_path = File.realpath(File.expand_path('../..', __dir__))

showcases = YAML.load_file("#{__dir__}/showcases.yml")
template = ERB.new(DATA.read)

restart = (not ARGV.include?('--restart'))

Dir.chdir @git_path

index = OpenStruct.new(
  label: "index",
  redis: "index",
  scope: "__index__",
)

ENV['RAILS_APP_DB'] = index.label
system 'bin/rails db:create' unless File.exist? "db/#{index.label}.sqlite3"

@tenants = [index]
showcases.each do |year, list|
  list.each do |token, info|
    tenant = OpenStruct.new(
      label: "#{year}-#{token}",
      redis: "#{year}_#{token}",
      scope: "#{year}/#{token}",
      port:  info[:port]
    )

    ENV['RAILS_APP_DB'] = tenant.label
    system 'bin/rails db:create' unless File.exist? "db/#{tenant.label}.sqlite3"
    system 'bin/rails db:migrate'

    count = `sqlite3 db/#{tenant.label}.sqlite3 "select count(*) from events"`.to_i
    system 'bin/rails db:seed' if count == 0

    @tenants << tenant
  end
end

old_conf = IO.read(SHOWCASE_CONF) rescue nil
new_conf = template.result(binding)

if new_conf != old_conf
  STDERR.puts SHOWCASE_CONF
  IO.write SHOWCASE_CONF, new_conf
  restart = true
end

system 'brew services restart nginx' if restart

__END__
server {
  listen 9999;
  server_name localhost;

  # Tell Nginx and Passenger where your app's 'public' directory is
  root <%= @git_path %>/public;

  location /showcase {
    alias <%= @git_path %>/public;
    try_files $uri @index;
  }
 
  location @index {
    rewrite ^/showcase/(.*)$ /showcase/__index__/$1;
  }
  <% @tenants.each do |tenant| %>
  location <%= ROOT %>/<%= tenant.scope %> {
    # Turn on Passenger
    passenger_enabled on;
    passenger_ruby <%= RbConfig.ruby %>;
    passenger_friendly_error_pages on;
    passenger_min_instances 0;
    
    # Define tenant
    passenger_app_group_name showcase-<%= tenant.label %>;
    passenger_env_var RAILS_RELATIVE_URL_ROOT <%= ROOT %>;
    passenger_env_var RAILS_APP_DB <%= tenant.label %>;
    passenger_env_var RAILS_APP_SCOPE <%= tenant.scope %>;
    passenger_env_var RAILS_APP_REDIS am_event_<%= tenant.redis %>_production;
    passenger_env_var RAILS_PROXY_HOST https://rubix.intertwingly.net/;
    passenger_env_var PIDFILE <%= @git_path %>/tmp/pids/<%= tenant.label %>.pid;
  }

  location <%= ROOT %><%= tenant.cable %> {
    passenger_app_group_name showcase-<%= tenant.label %>-cable;
    passenger_force_max_concurrent_requests_per_process 0;
  }
  <% 

  end
  %>
}
