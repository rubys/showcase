require 'erb'
require 'yaml'

NGINX_SERVERS = "/opt/homebrew/etc/nginx/servers"

agents = Dir["#{NGINX_SERVERS}/showcase-*.conf"].map do |file|
  [File.basename(file, '.conf'), IO.read(file)]
end.to_h

@git_path = File.realpath(File.expand_path('../..', __dir__))

showcases = YAML.load_file("#{__dir__}/showcases.yml")
template = ERB.new(DATA.read)

restart = (not ARGV.include?('--restart'))

Dir.chdir @git_path

showcases.each do |year, list|
  list.each do |token, info|
    @label = "#{year}-#{token}"
    @redis = "#{year}_#{token}"
    @scope = "#{year}/#{token}"
    @port = info[:port]
    agent = template.result(binding)
    showcase = "showcase-#{@label}"

    if agents.delete(showcase) != agent
      IO.write("#{NGINX_SERVERS}/#{showcase}.conf", agent)
      puts "+ #{NGINX_SERVERS}/#{showcase}.conf"
      restart = true
    end

    ENV['RAILS_APP_DB'] = @label
    system 'bin/rails db:create' unless File.exist? "db/#{@label}.sqlite3"
    system 'bin/rails db:migrate'

    count = `sqlite3 db/#{@label}.sqlite3 "select count(*) from events"`.to_i
    system 'bin/rails db:seed' if count == 0
  end
end

agents.keys.each do |showcase|
  puts "- #{NGINX_SERVERS}/#{showcase}.conf"
  File.unlink("#{NGINX_SERVERS}/#{showcase}.conf")
  restart = true
end

system 'brew services restart nginx' if restart


__END__
server {
  listen <%= @port %>;
  server_name localhost;

  # Tell Nginx and Passenger where your app's 'public' directory is
  root <%= @git_path %>/public;
  
  # Turn on Passenger
  passenger_enabled on;
  passenger_ruby <%= RbConfig.ruby %>;
  passenger_friendly_error_pages on;
  
  # Define tenant
  passenger_env_var RAILS_RELATIVE_URL_ROOT /showcase;
  passenger_env_var RAILS_APP_DB <%= @label %>;
  passenger_env_var RAILS_APP_SCOPE <%= @scope %>;
  passenger_env_var RAILS_APP_CABLE wss://rubix.intertwingly.net/showcase/<%= @scope %>/cable;
  passenger_env_var RAILS_APP_REDIS am_event_<%= @redis %>_production;
  passenger_env_var RAILS_SERVE_STATIC_FILES true;
  passenger_env_var PIDFILE <%= @git_path %>/tmp/pids/<%= @label %>.pid;
}
