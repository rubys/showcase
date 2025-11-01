#!/bin/sh

# Navigator start hook - system configuration
# This runs on server start before any tenants load

# Copy storage configuration for non-Fly.io environments
if [ -z "$FLY_APP_NAME" ]; then
  if [ -f config/storage/development.yml ]; then
    cp config/storage/development.yml config/storage/production.yml
    echo "[$(date -Iseconds)] Copied storage configuration to production"
  else
    echo "[$(date -Iseconds)] Warning: config/storage/development.yml not found"
  fi
fi

# Configure Redis memory overcommit to prevent fork errors
# https://redis.io/docs/getting-started/faq/#background-saving-fails-with-a-fork-error-on-linux
if [ -w /proc/sys/vm/overcommit_memory ]; then
  echo 1 > /proc/sys/vm/overcommit_memory
  echo "[$(date -Iseconds)] Configured vm.overcommit_memory=1 for Redis"
else
  echo "[$(date -Iseconds)] Warning: Cannot write to /proc/sys/vm/overcommit_memory (not running as root?)"
fi
