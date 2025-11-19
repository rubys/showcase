# Map Generation Without Git Commits

## Status: ✅ Complete

## Executive Summary

**Problem:** Location updates require git commits and deployments (5-10 minutes). Showcase updates use S3-based workflow (30-60 seconds). Need same workflow for locations.

**Solution:** Create standalone `script/generate_and_upload_maps.rb` called by both:
1. `script/config-update` (quick config updates) - ensures maps are always current
2. Admin controllers (location/region changes) - immediate upload after edit

**Key Changes:**
- **New:** `script/generate_and_upload_maps.rb` - Standalone script (replaces inline generation)
- **Delete:** `script/reconfig` - Redundant with new script + config-update
- **Update:** `script/config-update` - Add Step 0: generate and upload maps
- **Update:** `sync_databases_s3.rb` - Upload map ERB files alongside index.sqlite3
- **Update:** Admin controllers - Call script after location/region changes
- **Update:** `bin/apply-changes.rb` - Remove inline map generation (call config-update instead)
- **Remove:** Configuration drift detection (S3 is source of truth)

**Result:** Location updates via admin UI, no git commits, 30-60 seconds vs 5-10 minutes.

## Deployment Environments

Three distinct deployment environments with different roles:

### Rubix (Admin Server)
- **Role:** Administrative server, source of truth for index.sqlite3 and maps
- **Operations:** Upload only, never download
- **S3 Access:** No S3 env vars, but has rclone.conf (parsed by sync_databases_s3.rb)
- **Storage:** No /data/db directory
- **Sync Method:** Uses `sync_databases_s3.rb` which handles rclone credentials and calls webhook on completion
- **Webhook Responsibilities:** Archives, pushes updates to Hetzner backup, sends Sentry alerts on failure

### Fly.io (Production)
- **Role:** User-facing production environment
- **Operations:** Download index and maps from S3 on start, resume, and config changes
- **S3 Access:** Has S3 env vars (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_ENDPOINT_URL_S3)
- **Storage:** /data/db present (persistent Fly.io volume)
- **Sync Method:** Direct S3 download via aws-sdk-s3

### Hetzner (Hot Backup)
- **Role:** Hot backup, available even if S3 is down
- **Operations:** Download index and maps from /data/db (synced via Rubix webhook)
- **S3 Access:** No S3 env vars (intentionally - must work when S3 is down)
- **Storage:** /data/db present (mapped to Kamal host drive)
- **Sync Method:** Files pushed to /data/db by Rubix webhook

### Download Logic (All Environments)

```ruby
def download_maps_and_index
  if s3_env_vars_present?
    # Fly.io: Download from S3
    download_from_s3
  elsif Dir.exist?('/data/db')
    # Hetzner: Copy from /data/db (synced via webhook)
    copy_from_data_db
  else
    # Rubix or fallback: Do nothing, use git-tracked files
    # Map ERB files in git serve as fallback
  end
end
```

### Upload Logic (Rubix Only)

All uploads go through `sync_databases_s3.rb`:
- Parses rclone.conf for credentials
- Uploads to S3 (Tigris)
- Calls webhook on completion
- Webhook archives, pushes to Hetzner, sends Sentry alerts on failure

This keeps a clean division of labor: `sync_databases_s3.rb` updates S3, webhook handles distribution.

## Overview

Currently, adding or updating a location requires:
1. Update `db/index.sqlite3` (locations table)
2. Generate `config/tenant/map.yml` using Node.js (makemaps.js)
3. Commit `config/tenant/map.yml` to git
4. Generate map ERB partials (`app/views/event/_*map.html.erb`)
5. Commit map ERB files to git
6. Deploy to production

**Goal:** Enable location updates without committing files to git, similar to how showcase creation now works.

## Current Process

### Development Machine (bin/apply-changes.rb)

1. Admin updates locations in `db/index.sqlite3` via Rails admin UI
2. Rails generates `db/map.yml` from database (RegionConfiguration.generate_map_data)
3. `bin/apply-changes.rb` detects `db/map.yml` change
4. Copies `db/map.yml` → `config/tenant/map.yml`
5. Runs `node utils/mapper/makemaps.js` which:
   - Reads `config/tenant/map.yml`
   - Adds x,y projection coordinates for each location
   - Downloads/processes shapefiles for US/EU/AU/JP maps
   - Generates SVG paths for map backgrounds
   - Writes updated `config/tenant/map.yml` with x,y coordinates
   - Generates `app/views/event/_usmap.html.erb`, `_eumap.html.erb`, etc.
6. Git detects changes to `config/tenant/map.yml` and `app/views/event/*.erb`
7. Commits and deploys

### Production Machine (script/update_configuration.rb)

- **Does NOT regenerate map.yml** (line 106 comment: "would need node/makemaps.js")
- Uses pre-built map.yml and ERB files from Docker image
- Only regenerates showcases.yml and navigator config

## Problem Statement

When an admin adds/updates a location:
- `db/index.sqlite3` is updated
- `db/map.yml` is regenerated
- "Update Configuration" syncs to production machines
- **BUT** map.yml with x,y coordinates and map ERB files are NOT regenerated
- Must commit files to git and redeploy Docker image

This breaks the "no git commits for config changes" workflow.

## Proposed Solution

### Option A: Pre-generate Maps at Docker Build Time

**Approach:** Generate all possible map variations during Docker build, serve statically

**Benefits:**
- No Node.js required on production or admin machines
- Fast runtime performance (no generation needed)
- Simpler deployment workflow
- Maps are static anyway (lat/lon → x/y is deterministic)

**Drawbacks:**
- **Still requires deployment to update maps** - defeats the goal of "no git commits"
- Can't add new locations without rebuilding Docker image
- **Not suitable for this use case**

### Option B: Generate Maps on Admin Machine, Upload to S3 (Recommended)

**Approach:** Admin machine has Node.js, generates maps, uploads to S3

**Benefits:**
- Production machines don't need Node.js
- Maps are generated with actual location data
- Simpler Docker image

**Implementation:**

1. **Admin machine generates complete map artifacts**
   ```ruby
   # After location update in locations_controller.rb
   RegionConfiguration.generate_map_data  # Creates db/map.yml
   system('node utils/mapper/makemaps.js')  # Adds x,y coords, generates ERB
   # Upload to S3:
   # - db/map.yml (with x,y coordinates)
   # - app/views/event/_usmap.html.erb
   # - app/views/event/_eumap.html.erb
   # - app/views/event/_aumap.html.erb
   # - app/views/event/_jpmap.html.erb
   ```

2. **Production machines download from S3**
   ```ruby
   # In script/update_configuration.rb or Navigator ready hook
   download_from_s3('db/map.yml', '/data/db/map.yml')
   download_from_s3('views/usmap.html.erb', '/rails/app/views/event/_usmap.html.erb')
   download_from_s3('views/eumap.html.erb', '/rails/app/views/event/_eumap.html.erb')
   download_from_s3('views/aumap.html.erb', '/rails/app/views/event/_aumap.html.erb')
   download_from_s3('views/jpmap.html.erb', '/rails/app/views/event/_jpmap.html.erb')
   ```

3. **Restart Rails processes to pick up new ERB templates**
   - Navigator can restart app pools when ERB files change
   - Or use view cache invalidation

**Drawbacks:**
- Requires uploading/downloading 5 files (map.yml + 4 ERB templates)
- ERB templates need to be writable in production (currently read-only after build)
- Requires Rails restart or cache invalidation

### Option C: Port Projection Logic to Ruby

**Approach:** Reimplement makemaps.js projection logic in Ruby

**Benefits:**
- No Node.js dependency anywhere
- Can run on production machines
- Single language

**Implementation:**

1. **Create lib/map_generator.rb** with:
   - D3-geo equivalent projection functions (Albers USA, Conic Conformal, etc.)
   - Shapefile processing (using rgeo gem)
   - SVG path generation
   - ERB template generation

2. **Update locations_controller.rb**
   ```ruby
   def update
     # ... save location ...
     MapGenerator.generate_all_maps
     # Generates map.yml with x,y coords and ERB templates
   end
   ```

3. **Production machines can regenerate**
   ```ruby
   # In script/update_configuration.rb
   MapGenerator.generate_all_maps
   ```

**Drawbacks:**
- Significant development effort (porting D3-geo projections)
- Maintaining parity with JavaScript implementation
- Performance may differ
- Additional gem dependencies (rgeo, rgeo-shapefile)

## Recommended Approach: Option B (Admin Generates, Upload to S3)

**Why:**
- No code deployment needed (maps served as static HTML via prerender)
- Admin machine already has Node.js
- Production uses existing prerender workflow
- Navigator CGI + ready hooks handle file updates automatically

**Key insight:** Maps are pre-rendered to static HTML, not rendered dynamically by Rails in production. The prerender task generates static files served by Navigator.

**Trade-off:**
- Requires S3 upload/download of map ERB templates
- Admin machine needs Node.js (already has it)

## Implementation Plan: Option B (Detailed)

### Current Workflow Context

**Admin Machine Workflow:**

The admin machine has two main scripts for applying configuration changes:

1. **script/reconfig** - Full regeneration script (runs map generation TWICE - will be deleted)
   - Regenerates tmp/regions.json and tmp/deployed.json from flyctl
   - Regenerates db/map.yml and config/tenant/map.yml from index.sqlite3
   - Runs makemaps.js if either file changed
   - Regenerates db/showcases.yml and config/tenant/showcases.yml from index.sqlite3
   - ISSUE: This script generates maps but does NOT upload to S3 or trigger production updates

2. **bin/apply-changes.rb** - Full deployment script (runs map generation ONCE)
   - Checks if remote index.sqlite3 is older than local → runs script/config-update if needed
   - Creates Fly.io machines for pending regions
   - Copies db/map.yml → config/tenant/map.yml and runs makemaps.js
   - Copies db/showcases.yml → config/tenant/showcases.yml and deployed-showcases.yml
   - Deploys code changes via `fly deploy`
   - Destroys duplicate/removed machines
   - Commits and pushes changes

3. **script/config-update** - Quick config update (called by ConfigUpdateJob)
   - Syncs index.sqlite3 to S3 (or rsync for Kamal)
   - Gets list of deployment targets (Fly machines or Kamal server)
   - POSTs to /showcase/update_config on each target
   - ISSUE: Does NOT generate or upload maps

**Admin Controller Actions:**

- `admin#apply` - Shows pending changes, detects drift, allows user to trigger apply
- `admin#trigger_config_update` - Enqueues ConfigUpdateJob which runs script/config-update
- `admin#create_region` and `admin#destroy_region` - Call `generate_map` after region changes
- `locations_controller#update` - Should call map generation (currently missing)

**Production Machine Workflow:**

Navigator supports CGI scripts and hooks that make this workflow possible:

```yaml
cgi_scripts:
  - path: "/showcase/update_config"
    script: "/rails/script/update_configuration.rb"
    method: POST
    user: root
    group: root
    timeout: 5m
    reload_config: config/navigator.yml  # Triggers ready hook after completion
    env:
      RAILS_DB_VOLUME: "/data/db"
      RAILS_ENV: production

hooks:
  server:
    ready:
    - command: "/rails/script/ready.sh"
      args: []
      timeout: 10m
      # This hook runs after Navigator startup AND after config reloads
      # It calls bin/prerender which regenerates static HTML files
```

**script/update_configuration.rb** (CGI endpoint):
- Downloads index.sqlite3 from S3
- Updates htpasswd from index.sqlite3
- Generates showcases.yml from index.sqlite3
- Generates navigator.yml
- ISSUE: Does NOT download map files (comment says "would need node/makemaps.js")

**script/ready.sh** (ready hook):
1. `bin/prerender` - Regenerates all static HTML from ERB templates
2. `bin/prepare.rb` - Updates event databases

When map ERB templates change, prerender automatically regenerates static HTML.

### Phase 1: S3 Storage Structure

Create S3 paths for map ERB templates alongside index.sqlite3:
- `s3://bucket/index.sqlite3` (already exists)
- `s3://bucket/views/event/_usmap.html.erb` (NEW)
- `s3://bucket/views/event/_eumap.html.erb` (NEW)
- `s3://bucket/views/event/_aumap.html.erb` (NEW)
- `s3://bucket/views/event/_jpmap.html.erb` (NEW)

**Note:** We only upload the generated ERB files. The intermediate `map.yml` file stays on admin machine - it's only used by makemaps.js during generation. The ERB files already contain all location data with x/y coordinates embedded.

### Phase 2: Admin Machine Workflow (Generate + Upload)

#### Key Changes

1. **Create standalone script: script/generate_and_upload_maps.rb**
   - This replaces map generation functionality in script/reconfig
   - Can be called standalone (like script/config-update)
   - Does NOT require Rails environment (uses minimal Ruby with AWS SDK)
   - Runs: generate map data → makemaps.js → upload to S3

2. **Update script/config-update to call generate_and_upload_maps**
   - Add map generation BEFORE uploading index.sqlite3
   - Ensures maps are always current when config updates run

3. **Delete script/reconfig**
   - Redundant with generate_and_upload_maps + config-update combination
   - Was running map generation twice unnecessarily
   - Configuration drift detection no longer needed (S3 is source of truth)

4. **Update locations_controller.rb**
   - Call generate_and_upload_maps after location save
   - Automatically triggers when admin updates location via UI

#### Implementation: script/generate_and_upload_maps.rb

**New standalone script** (can run without Rails):

```ruby
#!/usr/bin/env ruby

require 'json'
require 'yaml'
require 'fileutils'
require 'open3'

# This script runs standalone (no Rails dependency)
# It's called by:
# - script/config-update (before syncing index.sqlite3)
# - locations_controller.rb (after location updates)

# Ensure tmp directory exists
FileUtils.mkdir_p('tmp')

puts "Generating and uploading map files..."
puts "=" * 70

# Load configuration
git_path = File.realpath(File.expand_path('..', __dir__))
dbpath = ENV.fetch('RAILS_DB_VOLUME') { "#{git_path}/db" }
index_db = File.join(dbpath, 'index.sqlite3')

unless File.exist?(index_db)
  puts "ERROR: index.sqlite3 not found at #{index_db}"
  exit 1
end

# Step 1: Generate map data from database
puts "\nStep 1: Generating map.yml from index.sqlite3..."
puts "-" * 70

# Option A: Use Rails (if available)
# Option B: Direct SQLite query (standalone)
# For now, use Rails since we need RegionConfiguration module

# Set database environment
ENV['DATABASE_URL'] = "sqlite3:#{index_db}"

# Load minimal Rails environment
require_relative '../config/environment'

# Generate map data using shared module
map_data = RegionConfiguration.generate_map_data

puts "   → Found #{map_data['regions'].size} deployed regions"
puts "   → Found #{map_data['studios'].size} studio locations"

# Write YAML to tmp directory
map_yml_path = File.join(git_path, 'tmp/map.yml')
new_map_yaml = YAML.dump(map_data)

# Check if map data actually changed (Layer 1 optimization)
if File.exist?(map_yml_path)
  old_map_yaml = File.read(map_yml_path)
  if old_map_yaml == new_map_yaml
    puts "   ✓ Map data unchanged, skipping generation and upload"
    exit 0  # Early exit - nothing to do
  end
end

File.write(map_yml_path, new_map_yaml)
puts "   ✓ Map data changed, wrote tmp/map.yml"

# Step 2: Run makemaps.js to add x,y coordinates
puts "\nStep 2: Running makemaps.js to add x,y coordinates..."
puts "-" * 70

# Capture ERB file mtimes before generation (Layer 3 optimization)
erb_files = {
  'us' => File.join(git_path, 'app/views/event/_usmap.html.erb'),
  'eu' => File.join(git_path, 'app/views/event/_eumap.html.erb'),
  'au' => File.join(git_path, 'app/views/event/_aumap.html.erb'),
  'jp' => File.join(git_path, 'app/views/event/_jpmap.html.erb')
}

before_mtimes = erb_files.transform_values do |path|
  File.exist?(path) ? File.mtime(path) : Time.at(0)
end

# Run makemaps.js (reads/writes tmp/map.yml per utils/mapper/files.yml)
# makemaps.js has built-in change detection (Layer 2 optimization)
Dir.chdir(git_path) do
  stdout, stderr, status = Open3.capture3('node', 'utils/mapper/makemaps.js')
  puts stdout unless stdout.empty?
  $stderr.puts stderr unless stderr.empty?

  unless status.success?
    puts "ERROR: makemaps.js failed with exit code #{status.exitstatus}"
    exit 1
  end
end

puts "   ✓ makemaps.js completed successfully"

# Step 3: Upload changed ERB files to S3
puts "\nStep 3: Uploading changed map ERB files to S3..."
puts "-" * 70

# Check which files actually changed (Layer 3 optimization)
uploaded = []
skipped = []

erb_files.each do |region, local_path|
  after_mtime = File.exist?(local_path) ? File.mtime(local_path) : Time.at(0)

  if after_mtime > before_mtimes[region]
    s3_path = "views/event/#{File.basename(local_path)}"
    puts "   → Uploading #{File.basename(local_path)} (#{region} map changed)"

    # Use S3Sync module (requires Rails)
    S3Sync.upload(local_path, s3_path)
    uploaded << region
  else
    skipped << region
  end
end

puts "\n" + "=" * 70
if uploaded.any?
  puts "SUCCESS: Uploaded #{uploaded.length} map(s): #{uploaded.join(', ')}"
else
  puts "SUCCESS: All maps up to date (0 uploads)"
end
puts "   Skipped: #{skipped.join(', ')}" if skipped.any?
puts "=" * 70
```

#### Integration Points

**1. Update script/config-update**

Add map generation at the beginning (before Step 1):

```ruby
# Step 0: Generate and upload maps
puts "Step 0: Generating and uploading map files..."
puts "=" * 50

script_path = File.expand_path('generate_and_upload_maps.rb', __dir__)

if options[:dry_run]
  puts "Would run: ruby #{script_path}"
else
  ruby_path = RbConfig.ruby
  stdout, stderr, status = Open3.capture3(ruby_path, script_path)

  puts stdout
  puts stderr unless stderr.empty?

  unless status.success?
    puts "Error: Map generation failed with exit code #{status.exitstatus}"
    exit 1
  end
end

puts "\n"

# Step 1: Sync index database (existing code)
# ...
```

**2. Update locations_controller.rb**

Add after location save:

```ruby
# app/controllers/locations_controller.rb
def update
  @location.update!(location_params)

  # Generate and upload maps
  system('ruby', Rails.root.join('script/generate_and_upload_maps.rb').to_s)

  # Trigger config update on production
  # (This is already handled by user clicking "Update Configuration" button)

  redirect_to admin_regions_path, notice: 'Location updated'
end
```

**Alternative:** Call from admin_controller.rb's generate_map method:

```ruby
# app/controllers/concerns/configurator.rb
def generate_map
  # Call standalone script instead of inline generation
  script_path = Rails.root.join('script/generate_and_upload_maps.rb')
  system('ruby', script_path.to_s)
end
```

This means existing calls to `generate_map` (in admin#create_region, admin#destroy_region) automatically upload maps.

### Phase 3: Production Workflow (Download + Prerender)

Maps need to be downloaded in two scenarios:
1. **Initial deployment/startup** - Maps not in Docker image
2. **Config update** - Admin triggers update via CGI endpoint

#### Scenario 1: Initial Deployment (script/nav_initialization.rb)

This script runs as a Navigator ready hook during maintenance mode startup. It currently:
- Syncs index.sqlite3 from S3 (Thread 1)
- Updates htpasswd (Thread 2)
- Generates showcases.yml
- Generates navigator.yml

**Add map download to Thread 1** (after S3 sync, before showcases.yml generation):

```ruby
# Thread 1: S3 sync (slowest operation, ~3s) - Fly.io only
if fly_io?
  threads << Thread.new do
    puts "Syncing databases from S3..."
    system "ruby #{git_path}/script/sync_databases_s3.rb --index-only --safe --quiet"
    puts "  ✓ S3 sync complete"

    # Download map ERB templates from S3 (NEW)
    puts "Downloading map ERB templates from S3..."
    begin
      require 'aws-sdk-s3'

      s3_client = Aws::S3::Client.new(
        region: 'auto',
        endpoint: ENV['AWS_ENDPOINT_URL_S3'],
        access_key_id: ENV['AWS_ACCESS_KEY_ID'],
        secret_access_key: ENV['AWS_SECRET_ACCESS_KEY']
      )

      bucket = 'showcase-data'
      downloaded = []

      ['_usmap', '_eumap', '_aumap', '_jpmap'].each do |map_name|
        s3_key = "views/event/#{map_name}.html.erb"
        local_path = "#{git_path}/app/views/event/#{map_name}.html.erb"

        begin
          # Download from S3 (overwrites local file)
          s3_client.get_object(
            bucket: bucket,
            key: s3_key,
            response_target: local_path
          )
          downloaded << map_name
        rescue Aws::S3::Errors::NoSuchKey
          # Map doesn't exist in S3 yet (first bootstrap)
          puts "  → #{map_name}.html.erb not found in S3 (will use Docker image version if present)"
        end
      end

      puts "  ✓ Downloaded #{downloaded.length} map(s): #{downloaded.join(', ')}" if downloaded.any?
    rescue => e
      puts "  ✗ Map download failed: #{e.message}"
      puts "    Using Docker image maps (may be outdated)"
    end
  end
end
```

**Note:** During initial deployment, maps from Docker image serve as fallback until first admin update.

**Hook Consolidation Opportunity:**

Currently `build_hooks_config` in `app/controllers/concerns/configurator.rb` has two separate start hooks:
1. `/rails/script/hook_navigator_start.sh` - System configuration (Redis, etc.)
2. `/rails/script/update_htpasswd.rb` - Updates htpasswd

And one resume hook:
3. `script/nav_initialization.rb` - Full initialization (S3 sync, htpasswd, maps, config generation)

**Recommendation:** Consolidate start hooks by having `hook_navigator_start.sh` call `update_htpasswd.rb`, reducing to:
- **Start hook:** `hook_navigator_start.sh` → calls `update_htpasswd.rb` → system config + htpasswd
- **Resume hook:** `nav_initialization.rb` → S3 sync + maps download + htpasswd + config generation

Or even simpler: Have `nav_initialization.rb` run on both start and resume (with a flag to skip S3 sync on start if not needed).

This would make the hook configuration cleaner and ensure maps are downloaded consistently.

#### Scenario 2: Config Update (script/update_configuration.rb)

**script/update_configuration.rb** (CGI endpoint called by admin):

```ruby
# Operation 1: Download index.sqlite3 from S3 (already exists)
run_command("Database sync", 'ruby', script_path, '--index-only')

# Operation 2: Download map ERB templates from S3 (NEW)
log "Operation 2.5/4: Downloading map ERB templates from S3"
log "-" * 70

begin
  # Download ERB templates to /rails/app/views/event/
  # These contain the complete map HTML with location x,y coordinates already embedded
  # Only download files that exist in S3 (some may not have been uploaded if unchanged)
  rails_root = Rails.root.to_s
  downloaded = []
  skipped = []

  ['_usmap', '_eumap', '_aumap', '_jpmap'].each do |map_name|
    s3_path = "views/event/#{map_name}.html.erb"
    local_path = "#{rails_root}/app/views/event/#{map_name}.html.erb"

    if S3Sync.exists?(s3_path)
      # Check if S3 version is newer than local version
      s3_mtime = S3Sync.mtime(s3_path)
      local_mtime = File.exist?(local_path) ? File.mtime(local_path) : Time.at(0)

      if s3_mtime > local_mtime
        S3Sync.download(s3_path, local_path)
        downloaded << map_name
      else
        skipped << "#{map_name} (already current)"
      end
    else
      skipped << "#{map_name} (not in S3)"
    end
  end

  log "SUCCESS: Map ERB templates downloaded: #{downloaded.join(', ')}" if downloaded.any?
  log "INFO: Skipped: #{skipped.join(', ')}" if skipped.any?
rescue => e
  log "ERROR: Map download failed: #{e.message}"
  # Continue anyway - use existing maps
end

# Operation 3: Update htpasswd (already exists)
# Operation 4: Generate showcases.yml (already exists)
# Operation 5: Generate navigator.yml (already exists)
# Operation 6: Touch navigator.yml mtime to trigger reload (already exists)
```

**script/ready.sh** (Navigator ready hook - triggered after config reload):

This already exists and does exactly what we need:
```bash
# Step 1: Run prerender (regenerates static HTML from ERB templates)
RAILS_ENV=production bin/prerender

# Step 2: Update event databases
ruby bin/prepare.rb (reads tmp/tenants.list)
```

The prerender task will automatically pick up the new ERB templates and regenerate static HTML files.

### Phase 4: Remove Git-Tracked Files, Update Configuration, Delete Obsolete Scripts

1. **Update utils/mapper/files.yml**
   Change map_yaml path from config/tenant to tmp:
   ```yaml
   files:
     map_yaml: ../../tmp/map.yml  # Changed from ../../config/tenant/map.yml
   ```

2. **Add tmp/map.yml to .gitignore** (if not already present)
   ```
   tmp/map.yml
   ```

   **Note:** Do NOT add map ERB files to .gitignore. Keep them in git as fallback:
   - Useful if S3 download fails
   - Useful for Hetzner before first webhook sync
   - They may be stale but still functional

3. **Remove config/tenant/map.yml from git**
   ```bash
   git rm config/tenant/map.yml
   git commit -m "Remove git-tracked map.yml - now using tmp/map.yml as transient build artifact"
   ```

   **Note:** Keep map ERB files in git - they serve as fallback if other operations fail.

4. **Delete script/reconfig**
   ```bash
   git rm script/reconfig
   ```

   **Why:** This script is now redundant. It performed:
   - Regenerated tmp/regions.json and tmp/deployed.json → Still needed, but rarely used
   - Regenerated map files → Now handled by script/generate_and_upload_maps.rb
   - Regenerated showcases files → Already in admin_controller.rb's generate_showcases
   - Did NOT upload to S3 or trigger production updates → Incomplete workflow

   **Replacement workflow:**
   ```bash
   # Old way (script/reconfig):
   script/reconfig  # Generate everything locally, no S3, no production update

   # New way (explicit steps):
   # 1. Regenerate region data (if needed):
   #    - tmp/regions.json: flyctl platform regions --json
   #    - tmp/deployed.json: flyctl regions list --json
   # 2. Generate and upload maps:
   ruby script/generate_and_upload_maps.rb
   # 3. Trigger production update:
   ruby script/config-update  # Generates showcases, uploads index.sqlite3, triggers production
   ```

   **Note:** Region JSON regeneration is rarely needed (only when Fly.io adds new regions). Can be done manually or added to a new script if needed.

5. **Update bin/apply-changes.rb**
   Remove the map.yml copy and makemaps.js call (lines 62-69):
   ```ruby
   # DELETE THIS SECTION:
   if File.exist? 'db/map.yml'
     new_map = IO.read('db/map.yml')
     if new_map != IO.read('config/tenant/map.yml')
       IO.write('config/tenant/map.yml', new_map)
     end
     exit 1 unless system 'node utils/mapper/makemaps.js'
   end
   ```

   **Why:** Maps are now uploaded to S3 by script/generate_and_upload_maps.rb (called by script/config-update).

   **Note:** bin/apply-changes.rb still handles:
   - Creating/destroying Fly.io machines (region changes)
   - Deploying code changes (fly deploy)
   - Committing/pushing git changes

   But it will now call script/config-update (which calls generate_and_upload_maps) instead of generating maps inline.

6. **Remove configuration drift detection from admin#apply**

   **File:** app/controllers/admin_controller.rb (lines 162-165)

   ```ruby
   # DELETE THIS SECTION:
   # Detect drift between deployed snapshot and git-tracked file
   if File.exist?('db/deployed-showcases.yml')
     git_showcases = YAML.load_file('config/tenant/showcases.yml').values.reduce {|a, b| a.merge(b)}
     @showcases_drift = (before != git_showcases)
   end
   ```

   **Why:** With S3-based workflow, there is no "git-tracked file" to drift from. S3 is the source of truth.

   **View changes:** Remove showcases drift warning from app/views/admin/apply.html.erb

7. **Clean up old references**
   Search codebase for `config/tenant/map.yml` and update to `tmp/map.yml` if needed:

   ```bash
   # Find remaining references
   git grep "config/tenant/map.yml"

   # Expected remaining references:
   # - lib/region_configuration.rb (Map#determine_papersize) - reads map to determine region papersize
   #   This should be updated to read from tmp/map.yml or directly from S3
   ```

## Benefits After Migration

1. **No git commits needed** - Add/update locations via admin UI, no deployment required
2. **Faster updates** - Config update via CGI (30-60 seconds) vs Docker deploy (5-10 minutes)
3. **Efficient uploads** - Only changed maps uploaded (e.g., Virginia update → only US map)
4. **Efficient downloads** - Production only downloads maps newer than local versions
5. **Automatic propagation** - S3 → all production regions via existing update_configuration flow
6. **Consistent with showcase workflow** - Both use index.sqlite3 → S3 → production pattern
7. **Leverages existing infrastructure** - Navigator CGI, ready hooks, prerender all already working
8. **No new dependencies** - Admin already has Node.js, production already has S3 sync

### Change Detection Optimization (3 Layers)

**Layer 1 - Early exit (Admin):**
- Generate map_data from database (lat/lon for all locations)
- Compare with existing tmp/map.yml content
- If identical, return immediately (no makemaps.js, no uploads)
- **Benefit:** Updating non-location data (showcase name, etc.) does zero work

**Layer 2 - Selective generation (makemaps.js):**
- Built-in change detection (line 176: checks if SVG content changed)
- Only rewrites ERB files when map content actually differs
- **Benefit:** Location metadata changes don't trigger unnecessary rewrites

**Layer 3 - Selective upload (Admin):**
- Compare ERB file mtimes before/after makemaps.js
- Only upload files that were modified
- **Benefit:** Regional changes only affect one map file

**Layer 4 - Selective download (Production):**
- Check S3 mtime vs local mtime
- Only download if S3 version is newer
- **Benefit:** Machines with current maps skip download

**Typical scenarios:**
- Update showcase name → Early exit, 0 files (Layer 1)
- Update location description (no lat/lon change) → Early exit, 0 files (Layer 1)
- Update Virginia location lat/lon → 1 file upload/download (Layers 2+3+4)
- Update Sydney location → 1 file upload/download (Layers 2+3+4)
- Add new Tokyo location → 1 file upload/download (Layers 2+3+4)
- No location changes → 0 files (Layer 1)

**Edge cases:**
- First deployment: All 4 files upload (bootstrap)
- Location moves between map regions: 2 files change (old + new map)
- Multiple locations in same region: 1 file (map consolidates all)

## Complete Workflow After Implementation

### Scenario 1: Admin updates a location

1. Edit location in Rails admin UI (updates `db/index.sqlite3`)
2. Save → Automatically calls `script/generate_and_upload_maps.rb`
   - Generates `tmp/map.yml` from database
   - Runs `node utils/mapper/makemaps.js` to add x,y coords + generate ERB files
   - Uploads only changed ERB files to S3 (map.yml stays local)
3. Click "Update Configuration" button → Triggers ConfigUpdateJob
4. ConfigUpdateJob runs `script/config-update`:
   - Step 0: Calls `script/generate_and_upload_maps.rb` again (ensures maps are current)
   - Step 1: Uploads `index.sqlite3` to S3
   - Step 2: Gets list of Fly.io machines
   - Step 3: Posts to `/showcase/update_config` on each production region

5. Production machines (via CGI + hooks):
   - CGI script (`script/update_configuration.rb`) runs:
     - Download `index.sqlite3` from S3
     - Download changed ERB files from S3 (mtime comparison)
     - Update `htpasswd` from `index.sqlite3`
     - Generate `showcases.yml` from `index.sqlite3`
     - Generate `navigator.yml`
     - Touch `navigator.yml` to trigger config reload
   - Navigator detects change, runs ready hook (`script/ready.sh`):
     - `bin/prerender` regenerates static HTML from new ERB templates
     - `bin/prepare.rb` updates event databases
   - Updated maps now visible on all regions

**Total time:** ~30-60 seconds (vs 5-10 minutes for full deployment)

### Scenario 2: Admin adds/removes region

1. Click "Add Region" or "Remove Region" in admin UI
2. Admin controller calls `generate_map` (updated to call `script/generate_and_upload_maps.rb`)
   - Uploads changed map files to S3
3. Click "Apply Changes" button → Runs `bin/apply-changes.rb`
   - Calls `script/config-update` (which calls `generate_and_upload_maps.rb` again)
   - Creates/destroys Fly.io machines as needed
   - Deploys code if needed (fly deploy)
   - Commits/pushes git changes

**Total time:** ~5-10 minutes (includes machine provisioning and optional deployment)

### Scenario 3: Admin updates showcase (not location)

1. Edit showcase in Rails admin UI (updates `db/index.sqlite3`)
2. Click "Update Configuration" button → Triggers ConfigUpdateJob
3. ConfigUpdateJob runs `script/config-update`:
   - Step 0: Calls `script/generate_and_upload_maps.rb`
     - **Early exit:** Map data unchanged, skips generation/upload (0 files)
   - Step 1: Uploads `index.sqlite3` to S3
   - Step 2-3: Updates production machines

4. Production machines download index.sqlite3, regenerate showcases.yml and navigator.yml

**Total time:** ~20-30 seconds (faster due to early exit optimization)

## Rollback Plan

If issues arise after Phase 4 (removing from git):
- Map files are in git history, can be restored
- Revert to committing map.yml and ERB files
- Remove S3 upload/download code
- ConfigUpdateJob continues to work (just doesn't update maps)

Before Phase 4, rollback is even simpler:
- S3 uploads are additive (doesn't break existing workflow)
- Git-tracked files still present as fallback

## Timeline Estimate

**Option B (Recommended):**
- Phase 1: 1 hour (S3 bucket structure planning, test uploads/downloads)
- Phase 2: 3-4 hours (create script/generate_and_upload_maps.rb, integrate with script/config-update and controllers)
- Phase 3: 2-3 hours (production download logic in update_configuration.rb, testing with CGI + hooks)
- Phase 4: 2-3 hours (remove from git, delete script/reconfig, update bin/apply-changes.rb, remove drift detection, clean up references)
- **Total:** 8-11 hours

**Breakdown of Phase 2 changes:**
- Create script/generate_and_upload_maps.rb: 1-2 hours
  - Standalone script that loads Rails, generates maps, uploads to S3
  - Four-layer optimization (early exit, selective generation, selective upload, selective download)
- Integrate with script/config-update: 30 minutes
  - Add Step 0 that calls generate_and_upload_maps.rb before syncing index.sqlite3
- Update locations_controller.rb or admin_controller.rb: 30 minutes
  - Call generate_and_upload_maps.rb after location save
- Update admin_controller.rb's generate_map method: 30 minutes
  - Replace inline generation with call to script
- Testing and debugging: 1 hour

**Breakdown of Phase 4 changes:**
- Delete script/reconfig: 15 minutes
- Update bin/apply-changes.rb: 30 minutes (remove map generation section)
- Remove drift detection from admin#apply: 30 minutes (controller + view)
- Update utils/mapper/files.yml: 15 minutes
- Update .gitignore and git rm files: 15 minutes
- Clean up config/tenant/map.yml references: 30 minutes (search codebase, update determine_papersize)
- Testing: 1 hour

**Note:** No file permission changes needed - both update_configuration.rb CGI script and ready hook run as root, so they can write to /rails/app/views/event/ directly.

**Option A (Build-time + client-side):**
- Requires deployment to update projections: **Not suitable**

**Option C (Ruby Projection):**
- 20-30 hours (porting D3-geo): **Too much maintenance burden**

## Refactoring Opportunities

The plan has **duplicate code** in three places that should be **shared**:

### 1. Map Download Logic (Duplicated 3 times)

**Current plan has inline download code in:**
- `script/nav_initialization.rb` - Start/resume hook
- `script/update_configuration.rb` - Config update CGI

**Problem:** Same logic (iterate 4 files, download from S3 or /data/db, check mtime, handle errors) duplicated

**Refactoring:** Create **`lib/map_downloader.rb`** module:

```ruby
module MapDownloader
  MAP_FILES = %w[_usmap _eumap _aumap _jpmap].freeze

  def self.download(rails_root: '/rails', quiet: false)
    # Determine source based on environment
    if s3_env_vars_present?
      # Fly.io: Download from S3
      download_from_s3(rails_root: rails_root, quiet: quiet)
    elsif Dir.exist?('/data/db')
      # Hetzner: Copy from /data/db (synced via webhook)
      copy_from_data_db(rails_root: rails_root, quiet: quiet)
    else
      # Rubix or fallback: Do nothing, use git-tracked files
      { downloaded: [], skipped: MAP_FILES.map { |f| "#{f} (using git fallback)" } }
    end
  end

  def self.s3_env_vars_present?
    %w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_ENDPOINT_URL_S3].all? { |var| ENV[var] }
  end

  def self.download_from_s3(rails_root:, quiet:)
    downloaded = []
    skipped = []

    MAP_FILES.each do |map_name|
      s3_key = "views/event/#{map_name}.html.erb"
      local_path = File.join(rails_root, 'app/views/event', "#{map_name}.html.erb")

      begin
        if S3Sync.exists?(s3_key)
          s3_mtime = S3Sync.mtime(s3_key)
          local_mtime = File.exist?(local_path) ? File.mtime(local_path) : Time.at(0)

          if s3_mtime > local_mtime
            S3Sync.download(s3_key, local_path)
            downloaded << map_name
          else
            skipped << "#{map_name} (already current)"
          end
        else
          skipped << "#{map_name} (not in S3)"
        end
      rescue => e
        puts "  ✗ Failed to download #{map_name}: #{e.message}" unless quiet
      end
    end

    { downloaded: downloaded, skipped: skipped }
  end

  def self.copy_from_data_db(rails_root:, quiet:)
    downloaded = []
    skipped = []

    MAP_FILES.each do |map_name|
      source_path = "/data/db/views/event/#{map_name}.html.erb"
      local_path = File.join(rails_root, 'app/views/event', "#{map_name}.html.erb")

      begin
        if File.exist?(source_path)
          source_mtime = File.mtime(source_path)
          local_mtime = File.exist?(local_path) ? File.mtime(local_path) : Time.at(0)

          if source_mtime > local_mtime
            FileUtils.cp(source_path, local_path)
            downloaded << map_name
          else
            skipped << "#{map_name} (already current)"
          end
        else
          skipped << "#{map_name} (not in /data/db)"
        end
      rescue => e
        puts "  ✗ Failed to copy #{map_name}: #{e.message}" unless quiet
      end
    end

    { downloaded: downloaded, skipped: skipped }
  end
end
```

**Usage in all three scripts:**
```ruby
# script/nav_initialization.rb (in Thread 1)
result = MapDownloader.download(rails_root: git_path)
puts "  ✓ Downloaded #{result[:downloaded].length} map(s): #{result[:downloaded].join(', ')}"

# script/update_configuration.rb (Operation 2.5)
result = MapDownloader.download(rails_root: Rails.root.to_s)
log "SUCCESS: Downloaded: #{result[:downloaded].join(', ')}"
```

The `download` method automatically determines the source based on environment:
- **Fly.io:** Downloads from S3 (env vars present)
- **Hetzner:** Copies from /data/db (no env vars, but /data/db exists)
- **Rubix:** Does nothing (uses git-tracked files as fallback)

**Benefits:**
- Single source of truth for map download logic
- Easier to add mtime comparison, error handling, retry logic
- Can easily add metrics/logging
- Reduces plan from ~100 lines to ~20 lines per location

### 2. Map Upload Logic (via sync_databases_s3.rb)

**Current plan:** Uploads should go through `sync_databases_s3.rb` which:
- Parses rclone.conf for credentials
- Uploads to S3 (Tigris)
- Calls webhook on completion (archives, pushes to Hetzner, sends Sentry alerts)

**Refactoring:** Update `sync_databases_s3.rb` to also upload map ERB files:

```ruby
# In sync_databases_s3.rb, after uploading index.sqlite3:

# Upload map ERB templates
MapDownloader::MAP_FILES.each do |map_name|
  local_path = File.join(git_path, 'app/views/event', "#{map_name}.html.erb")
  s3_key = "views/event/#{map_name}.html.erb"

  if File.exist?(local_path)
    upload_to_s3(local_path, s3_key)
  end
end
```

**Note:** The `generate_and_upload_maps.rb` script generates the maps locally, then calls `sync_databases_s3.rb` to upload them (along with index.sqlite3). This maintains the clean division of labor where sync_databases_s3.rb handles all S3 interactions and webhook notifications.

### 3. ERB File Path Constants (Duplicated 4+ times)

**Current plan has hardcoded paths:**
- `app/views/event/_usmap.html.erb` (repeated ~10 times)
- `app/views/event/_eumap.html.erb` (repeated ~10 times)
- etc.

**Refactoring:** Use `MapDownloader::MAP_FILES` constant everywhere

### 4. S3 Bucket Name (Hardcoded)

**Current plan:** `bucket = 'showcase-data'` appears in multiple places

**Refactoring:** Add to S3Sync module or environment variable

## Summary of Refactoring

**Before refactoring:**
- 3 locations with ~50 lines of duplicate download code
- 1 location with ~30 lines of upload code
- Hardcoded file paths and bucket names everywhere

**After refactoring:**
- 1 shared `lib/map_downloader.rb` module (~80 lines total)
- 3 locations with ~3 lines of download code each
- 1 location with ~5 lines of upload code
- Centralized constants

**Reduction:** ~200 lines of plan → ~100 lines, easier to maintain

## References

- Current implementation: `utils/mapper/makemaps.js`
- Region configuration: `lib/region_configuration.rb`
- Related plan: `plans/REMOVE_SHOWCASES_YML_FROM_GIT.md` (Phase 4 mentions this)
