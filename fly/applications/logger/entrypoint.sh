#!/bin/bash
set -e

# Start Vector in the background
echo "Starting Vector log aggregator..."
vector --config /etc/vector/vector.toml &
VECTOR_PID=$!

# Start the main application
echo "Starting logger application..."
exec thrust bun run start

# Note: When the main process exits, Docker will stop the container
# and Vector will be terminated automatically