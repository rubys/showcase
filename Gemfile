source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.0"

# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"

# Use sqlite3 as the database for Active Record
gem "sqlite3", "~> 2.1"

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"

# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"

# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"

# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails", "~> 4.3.0"

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Redis adapter to run Action Cable in production
gem "redis", ">= 4.0.1"

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Sass to process CSS
group :production do
  # gem "sassc-rails"
end

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ]
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Add speed badges [https://github.com/MiniProfiler/rack-mini-profiler]
  # gem "rack-mini-profiler"

  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"

  # Hot reloading for Hotwire
  gem "hotwire-spark"

  gem "fuzzy_match"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
  # gem "webdrivers"
  
  # Code coverage
  gem "simplecov", require: false
  gem "simplecov-html", require: false
end

gem "dockerfile-rails"

gem "sentry-ruby", "~> 5.26"
gem "sentry-rails", "~> 5.26"

gem "fast_excel", "~> 0.5.0"
gem "rqrcode", "~> 3.1"
gem "chronic", "~> 0.10.2"
gem "combine_pdf", "~> 1.0"
gem "kramdown", "~> 2.4"
gem "tomlrb", "~> 2.0"
gem "ansi-to-html", "~> 0.0.3"

gem "useragent", "~> 0.16.10"

gem "kamal", require: false

gem "csv", "~> 3.3"

gem "thruster", "~> 0.1.9"

gem "logger", "~> 1.6"

gem "aws-sdk-s3", "~> 1.176"

gem "geocoder", "~> 1.8"

gem "rubyzip", "~> 3.0"

gem "htauth", "~> 2.3"

gem "turbo_cable", github: "rubys/turbo_cable"
