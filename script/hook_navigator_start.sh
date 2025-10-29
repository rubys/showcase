#!/bin/sh

# Navigator start hook - system configuration
# This runs on server start before any tenants load

# Configure Redis memory overcommit to prevent fork errors
# https://redis.io/docs/getting-started/faq/#background-saving-fails-with-a-fork-error-on-linux
if [ -w /proc/sys/vm/overcommit_memory ]; then
  echo 1 > /proc/sys/vm/overcommit_memory
  echo "[$(date -Iseconds)] Configured vm.overcommit_memory=1 for Redis"
else
  echo "[$(date -Iseconds)] Warning: Cannot write to /proc/sys/vm/overcommit_memory (not running as root?)"
fi
