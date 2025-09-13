#!/bin/bash

# Test script to send a custom log entry via Vector to Hetzner

echo "Sending test logs to Hetzner via Vector HTTP with authentication..."

# Create a test log entry
TEST_LOG=$(cat <<EOF
{
  "message": "Test log from local Vector client at $(date)",
  "level": "info",
  "app": "showcase-test",
  "host": "$(hostname)",
  "test": true,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
}
EOF
)

echo "$TEST_LOG"
echo
echo "Starting Vector with test configuration..."
echo "The demo source will send 10 test events, then exit."
echo "Using RAILS_MASTER_KEY for authentication..."
echo

# Run Vector with our test config and RAILS_MASTER_KEY environment variable
# The demo source will automatically send 10 events and then Vector will exit
RAILS_MASTER_KEY=$(cat config/master.key) ~/.vector/bin/vector --config test-vector-client.toml

echo
echo "Test complete! Check logs on Hetzner:"
echo "ssh root@65.109.81.136 'docker exec logger-vector tail -20 /logs/showcase/\$(date +%Y-%m-%d).log.gz | zcat | jq .'"