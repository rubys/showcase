# Map Generation Without Git Commits

## Status: 📋 Planning

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

### Option A: Pre-generate Maps at Docker Build Time (Recommended)

**Approach:** Generate all possible map variations during Docker build, serve statically

**Benefits:**
- No Node.js required on production or admin machines
- Fast runtime performance (no generation needed)
- Simpler deployment workflow
- Maps are static anyway (lat/lon → x/y is deterministic)

**Implementation:**

1. **Docker build stage:** Generate complete map set
   ```dockerfile
   # In Dockerfile, add build stage for maps
   FROM node:20 AS map-builder
   WORKDIR /maps
   COPY utils/mapper /maps
   # Generate all maps with projections
   RUN npm install && node makemaps.js --all-locations
   ```

2. **Rails generates map.yml from DB → upload to S3**
   - Admin machine: After location change, generate `db/map.yml` from index.sqlite3
   - Upload `db/map.yml` to S3 alongside `index.sqlite3`
   - Production machines: Download `db/map.yml` from S3 during config update

3. **Runtime map rendering uses pre-built projections + dynamic data**
   - Pre-built: SVG map backgrounds (countries/states polygons)
   - Pre-built: Projection functions (lat/lon → x/y)
   - Dynamic: Location markers from `db/map.yml`
   - JavaScript controller applies projections client-side

**Files:**
- `app/views/event/_map.html.erb` - Loads JS controller, renders SVG container
- `app/javascript/controllers/map_controller.js` - Client-side projection logic
- `public/maps/*.json` - Pre-built projection data (from Docker build)

### Option B: Generate Maps on Admin Machine, Upload to S3

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

### Current Navigator Configuration

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

The ready hook (script/ready.sh) runs:
1. `bin/prerender` - Regenerates all static HTML from ERB templates
2. `bin/prepare.rb` - Updates event databases

This means when map ERB templates change, prerender automatically regenerates static HTML.

### Phase 1: S3 Storage Structure

Create S3 paths for map ERB templates alongside index.sqlite3:
- `s3://bucket/index.sqlite3` (already exists)
- `s3://bucket/views/event/_usmap.html.erb` (NEW)
- `s3://bucket/views/event/_eumap.html.erb` (NEW)
- `s3://bucket/views/event/_aumap.html.erb` (NEW)
- `s3://bucket/views/event/_jpmap.html.erb` (NEW)

**Note:** We only upload the generated ERB files. The intermediate `map.yml` file stays on admin machine - it's only used by makemaps.js during generation. The ERB files already contain all location data with x/y coordinates embedded.

### Phase 2: Admin Machine Workflow (Generate + Upload)

When admin updates a location via Rails UI:

1. **Save location to index.sqlite3**
   ```ruby
   # app/controllers/locations_controller.rb
   def update
     @location.update!(location_params)

     # Generate and upload maps
     generate_and_upload_maps

     # Trigger config update on production
     ConfigUpdateJob.perform_later(current_user.id)
   end
   ```

2. **Generate map artifacts (with change detection)**
   ```ruby
   # New method in locations_controller.rb or admin_controller.rb
   def generate_and_upload_maps
     # Step 1: Generate map.yml from database (without x,y)
     map_data = RegionConfiguration.generate_map_data
     new_map_yaml = YAML.dump(map_data)

     # Step 2: Check if map data actually changed
     map_yml_path = 'tmp/map.yml'
     if File.exist?(map_yml_path)
       old_map_yaml = File.read(map_yml_path)
       if old_map_yaml == new_map_yaml
         Rails.logger.info "Map data unchanged, skipping generation"
         return
       end
     end

     # Step 3: Write new map.yml to tmp/ (transient build artifact)
     File.write(map_yml_path, new_map_yaml)
     Rails.logger.info "Map data changed, regenerating maps"

     # Step 4: Capture ERB file mtimes before generation
     erb_files = {
       'us' => 'app/views/event/_usmap.html.erb',
       'eu' => 'app/views/event/_eumap.html.erb',
       'au' => 'app/views/event/_aumap.html.erb',
       'jp' => 'app/views/event/_jpmap.html.erb'
     }

     before_mtimes = erb_files.transform_values do |path|
       File.exist?(path) ? File.mtime(path) : Time.at(0)
     end

     # Step 5: Run makemaps.js to add x,y coords and generate ERB files
     # Note: makemaps.js reads/writes tmp/map.yml (configured in utils/mapper/files.yml)
     unless system('node utils/mapper/makemaps.js')
       raise "Map generation failed"
     end

     # Step 6: Upload only changed ERB files to S3
     # makemaps.js only rewrites files that changed (line 176 check)
     uploaded = []
     erb_files.each do |region, local_path|
       after_mtime = File.exist?(local_path) ? File.mtime(local_path) : Time.at(0)

       if after_mtime > before_mtimes[region]
         s3_path = "views/event/#{File.basename(local_path)}"
         Rails.logger.info "Uploading #{local_path} to S3 (#{region} map changed)"
         S3Sync.upload(local_path, s3_path)
         uploaded << region
       else
         Rails.logger.info "Skipping #{local_path} (#{region} map unchanged)"
       end
     end

     Rails.logger.info "Map generation complete. Uploaded: #{uploaded.join(', ')}"
   end
   ```

   **File organization:**
   - `tmp/map.yml` - Transient build artifact (generated from DB, consumed by makemaps.js)
   - `app/views/event/_*map.html.erb` - Generated ERB templates (uploaded to S3)

   **Optimization layers:**
   1. **Early exit:** Compare new map_data with existing tmp/map.yml, return if unchanged
   2. **Selective upload:** Only upload ERB files that were modified by makemaps.js

   **Typical scenarios:**
   - Update non-location field (showcase name, etc.) → Early exit, 0 files
   - Update location in Virginia → Only `_usmap.html.erb` uploads (1 file)
   - Update location in Sydney → Only `_aumap.html.erb` uploads (1 file)
   - Add new location → Affected map updates (1 file)

### Phase 3: Production Workflow (Download + Prerender)

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

### Phase 4: Remove Git-Tracked Files and Update Configuration

1. **Update utils/mapper/files.yml**
   Change map_yaml path from config/tenant to tmp:
   ```yaml
   files:
     map_yaml: ../../tmp/map.yml  # Changed from ../../config/tenant/map.yml
   ```

2. **Add to .gitignore** (if not already present)
   ```
   tmp/map.yml
   app/views/event/_usmap.html.erb
   app/views/event/_eumap.html.erb
   app/views/event/_aumap.html.erb
   app/views/event/_jpmap.html.erb
   ```

3. **Remove from git**
   ```bash
   git rm config/tenant/map.yml
   git rm app/views/event/_*map.html.erb
   git commit -m "Remove git-tracked map files - now generated from S3"
   ```

4. **Update bin/apply-changes.rb**
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

   Maps are now uploaded to S3 by locations_controller.rb

5. **Clean up old references**
   Search codebase for `config/tenant/map.yml` and update to `tmp/map.yml` if needed

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

**Admin updates a location:**
1. Edit location in Rails admin UI (updates `db/index.sqlite3`)
2. Click "Update Configuration" button
3. Admin machine:
   - Generates `db/map.yml` from database
   - Runs `node utils/mapper/makemaps.js` to add x,y coords + generate ERB files
   - Uploads 4 ERB files to S3 (map.yml stays local, only used by makemaps.js)
   - Uploads `index.sqlite3` to S3
   - Posts to `/showcase/update_config` on each production region

4. Production machines (via CGI + hooks):
   - Download `index.sqlite3` from S3
   - Download 4 ERB files from S3
   - Generate `showcases.yml` from `index.sqlite3`
   - Generate `navigator.yml`
   - Touch `navigator.yml` to trigger config reload
   - Navigator detects change, runs ready hook
   - Ready hook runs `bin/prerender` which regenerates static HTML
   - Updated maps now visible on all regions

**Total time:** ~30-60 seconds (vs 5-10 minutes for full deployment)

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
- Phase 1: 1 hour (S3 bucket structure planning)
- Phase 2: 2-3 hours (admin upload logic, integrate with locations_controller)
- Phase 3: 2-3 hours (production download logic, integrate with update_configuration.rb)
- Phase 4: 1 hour (remove from git, update .gitignore)
- **Total:** 6-8 hours

**Note:** No file permission changes needed - both update_configuration.rb CGI script and ready hook run as root, so they can write to /rails/app/views/event/ directly.

**Option A (Build-time + client-side):**
- Requires deployment to update projections: **Not suitable**

**Option C (Ruby Projection):**
- 20-30 hours (porting D3-geo): **Too much maintenance burden**

## References

- Current implementation: `utils/mapper/makemaps.js`
- Region configuration: `lib/region_configuration.rb`
- Related plan: `plans/REMOVE_SHOWCASES_YML_FROM_GIT.md` (Phase 4 mentions this)
