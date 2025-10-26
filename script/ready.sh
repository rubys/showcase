#!/bin/bash
# Navigator ready hook - optimization script
# Runs when Navigator is ready to serve requests:
#   - After initial startup
#   - After configuration reloads (CGI, SIGHUP, resume)
# These optimizations run asynchronously while Navigator serves requests

set -e

# Function for logging with timestamps
log() {
  echo "[$(date -Iseconds)] $@"
}

log "===================================================================="
log "Starting ready hook optimizations"
log "===================================================================="

# Change to Rails root directory
cd "$(dirname "$0")/.."

# 1. Run prerender (regenerate static HTML)
log ""
log "Step 1/2: Running prerender (regenerating static HTML)..."
log "--------------------------------------------------------------------"

if [ -f "bin/prerender" ]; then
  RAILS_ENV=production bin/prerender
  log "SUCCESS: Prerender completed"
else
  log "WARNING: bin/prerender not found, skipping prerender step"
fi

# 2. Download/update event databases
log ""
log "Step 2/2: Updating event databases..."
log "--------------------------------------------------------------------"

if [ -f "tmp/tenants.list" ]; then
  count=0
  while IFS= read -r db_path; do
    # Skip empty lines and comments
    [[ -z "$db_path" || "$db_path" =~ ^# ]] && continue

    log "Preparing database: $db_path"
    if ruby bin/prepare.rb "$db_path"; then
      count=$((count + 1))
    else
      log "WARNING: Failed to prepare $db_path (continuing with next)"
    fi
  done < tmp/tenants.list

  log "SUCCESS: Updated $count event databases"
else
  log "INFO: tmp/tenants.list not found, skipping event database updates"
fi

log ""
log "===================================================================="
log "Ready hook optimizations complete"
log "===================================================================="
