#!/bin/bash

# Install required gems
echo "Installing required gems..."
BUNDLE_GEMFILE=test_websocket_gemfile bundle install --quiet

echo "Starting WebSocket load test..."
echo "This will create 100 simultaneous connections to test the standalone Action Cable server"
echo ""

# Run the test
BUNDLE_GEMFILE=test_websocket_gemfile bundle exec ruby test_websocket_load.rb