#!/usr/bin/env ruby
# Standalone navigator config generator - minimal Rails loading
# Usage: ruby script/generate_navigator_config.rb

require 'bundler/setup'
require 'yaml'
require 'fileutils'
require 'pathname'
require 'active_support/core_ext/object/blank'  # For present? method
require 'active_support/string_inquirer'  # For Rails.env

# Setup minimal Rails-like environment
module Rails
  def self.root
    @root ||= Pathname.new(File.expand_path('..', __dir__))
  end

  module Logger
    def self.warn(msg)
      warn msg
    end
  end

  def self.logger
    Logger
  end

  def self.env
    @env ||= ActiveSupport::StringInquirer.new(ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'production')
  end
end

# Load dependencies
require_relative '../lib/region_configuration'
require_relative '../lib/prerender_configuration'

# Load Configurator
require_relative '../app/controllers/concerns/configurator'

# Create a minimal object that includes Configurator
class ConfigGenerator
  include Configurator
end

# Generate config
generator = ConfigGenerator.new
generator.generate_navigator_config

puts "Generated config/navigator.yml"
