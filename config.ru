# This file is used by Rack-based servers to start the application.

require_relative "config/environment"

if ENV['FLY_REGION']
  database = URI.parse(ENV['DATABASE_URL']).path
  system "ruby bin/prepare.rb #{database}"
end

map ENV.fetch 'RAILS_RELATIVE_URL_ROOT', '/' do
  run Rails.application
end

Rails.application.load_server
