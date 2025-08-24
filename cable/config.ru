# Standalone Action Cable server
# This runs Action Cable as a separate process, independent of the main Rails app

require_relative "../config/environment"
Rails.application.eager_load!

run ActionCable.server