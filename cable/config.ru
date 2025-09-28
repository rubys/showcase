# Standalone Action Cable server
# This runs Action Cable as a separate process, independent of the main Rails app

require_relative "../config/environment"
Rails.application.eager_load!

# Allow all origins in standalone mode since requests come through Navigator proxy
# Navigator handles authentication and security
ActionCable.server.config.allowed_request_origins = [/.*/]

# Mount Action Cable at the path expected by Navigator reverse proxy
map "/cable" do
  run ActionCable.server
end