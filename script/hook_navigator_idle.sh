#!/bin/bash

# Navigator idle hook script - syncs all databases when navigator goes idle
# This runs when the entire machine is about to go idle (no apps running)
# Only standard OS environment variables are available

# Exit on error
set -e

# Log the action
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Navigator idle hook triggered - syncing all databases"

# Change to Rails app directory
cd /rails

# Run the sync script for all databases
# Using --safe to prevent downloading databases owned by current region
# Check if FLY_APP_NAME is smooth to determine dry-run mode
if [ "$FLY_APP_NAME" = "smooth" ]; then
    bundle exec ruby script/sync_databases_s3.rb --safe
else
    bundle exec ruby script/sync_databases_s3.rb --safe --dry-run
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Navigator idle hook completed"