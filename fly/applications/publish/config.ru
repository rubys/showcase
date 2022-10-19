#!/usr/bin/env ruby
require 'bundler'

require 'rails'
require "action_controller/railtie"

require 'puppeteer-ruby'

Dir.chdir File.expand_path('..', __dir__)
Rails.env = 'publisher'

class App < Rails::Application
  config.eager_load = false
  config.root = __dir__
  config.consider_all_requests_local = true

  logger           = ActiveSupport::Logger.new(STDOUT)
  logger.formatter = config.log_formatter
  config.logger    = ActiveSupport::TaggedLogging.new(logger)

  routes.append do
    get '/wake', to: 'publish#wake'
    match '/', to: 'publish#url2pdf', via: [:get, :post] 
  end
end

class PublishController < ActionController::Base
  def wake
    render plain: 'OK', status: :ok
  end

  def url2pdf
    return render plain: 'missing url', status: :bad_request unless params[:url]

    Puppeteer.launch do |browser|
      page = browser.new_page
      page.goto(params[:url], wait_until: 'networkidle0')
      page.addStyleTag(content: "
        html {
          -webkit-print-color-adjust: exact !important;
          -webkit-filter: opacity(1) !important;
        }
      ")
      render plain: page.pdf(format: 'letter'), content_type: "application/pdf"
    end
  end
end

App.initialize!

map ENV.fetch('RAILS_RELATIVE_URL_ROOT', '') + '/publish' do
  run Rails.application
end

Rails.application.load_server
