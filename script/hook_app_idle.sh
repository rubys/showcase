#!/bin/bash

# App idle hook script - syncs a single database when an app goes idle
# Environment variables available:
# - RAILS_APP_DB: The database name for the app that went idle
# - PORT: The port the app was running on
# - All other app-specific environment variables

# Exit on error
set -e

# Log the action
echo "[$(date '+%Y-%m-%d %H:%M:%S')] App idle hook triggered for database: $RAILS_APP_DB"

# Only proceed if RAILS_APP_DB is set
if [ -z "$RAILS_APP_DB" ]; then
    echo "Error: RAILS_APP_DB not set, skipping sync"
    exit 1
fi

# Change to Rails app directory
cd /rails

# Run the sync script for this specific database
# Using --safe to prevent downloading in the region that owns the DB
# Using --dry-run for testing (remove when ready for production)
bundle exec ruby script/sync_databases_s3.rb --safe --only="$RAILS_APP_DB" --dry-run

echo "[$(date '+%Y-%m-%d %H:%M:%S')] App idle hook completed for database: $RAILS_APP_DB"