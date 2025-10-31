# This file is used by Rack-based servers to start the application.

require_relative "config/environment"

if ENV['DATABASE_URL']
  database = URI.parse(ENV['DATABASE_URL']).path
  # Run prepare if database doesn't exist or has zero size
  if !File.exist?(database) || File.size(database) == 0
    system "ruby bin/prepare.rb #{database}"
  end
end

map ENV.fetch 'RAILS_RELATIVE_URL_ROOT', '/' do
  run Rails.application
end

Rails.application.load_server
