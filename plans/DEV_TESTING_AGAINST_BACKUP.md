# Development Testing Against Backup Server

## Goal

Enable end-to-end testing of automated showcase requests from development environment against the backup Hetzner server (showcase.party) without impacting production Fly.io operations.

## Current Architecture

**Production Flow (smooth.fly.dev):**
1. User submits showcase request → routed to rubix machine
2. ShowcasesController creates showcase in index database
3. ConfigUpdateJob syncs index.sqlite3 to S3
4. script/config-update calls CGI endpoint on all active Fly machines
5. Each machine regenerates configs and triggers prerender
6. User redirected to `/showcase/:year/:location` on smooth.fly.dev

**Backup Server (showcase.party via Kamal on 65.109.81.136):**
- Single Hetzner server deployed via Kamal
- Uses same unified Dockerfile as Fly.io
- Different URL structure: no `/showcase` prefix (assets at `/assets/`)
- Bind-mounted volumes: `/home/rubys/db`, `/home/rubys/log`, `/home/rubys/storage`

## Feasibility Analysis

### ✅ Feasible with Minimal Changes

The request is feasible and can be accomplished with:

1. **Add `--target` flag to script/config-update**
   - Default: `fly` (current behavior)
   - Option: `kamal` (target Kamal server instead)
   - When `kamal`: Skip Fly machine discovery, directly POST to showcase.party CGI endpoint

2. **Update redirect URL in ShowcasesController**
   - Check `Rails.env.development?`
   - Redirect to `showcase.party` instead of `smooth.fly.dev`
   - Remove `/showcase` prefix for Kamal URLs

3. **Optional: Pass target through to job**
   - ConfigUpdateJob could accept optional `target:` parameter
   - Default to `fly`, allow override to `kamal`

## Detailed Implementation Plan

### Phase 1: Add `--target` Flag to script/config-update

**File:** `script/config-update`

**Changes:**

```ruby
# Add to options hash (line 10)
options = { verbose: false, dry_run: false, target: 'fly' }

# Add to OptionParser (after line 24)
opts.on("-t", "--target TARGET", [:fly, :kamal],
        "Target platform (fly, kamal). Default: fly") do |t|
  options[:target] = t
end
```

**Modify Step 2 - Machine Discovery (lines 58-126):**

```ruby
if options[:target] == :kamal
  puts "Target: Kamal (single server)"
  machine_ids = ['showcase.party']
  puts "Will update 1 Kamal server\n\n"
else
  # Existing Fly machine discovery logic
  puts "Target: Fly.io (multiple machines)"
  # ... existing code ...
end
```

**Modify Step 3 - Update Endpoint (lines 128-214):**

```ruby
if options[:target] == :kamal
  uri = URI.parse('https://showcase.party/update_config')
else
  uri = URI.parse('https://smooth.fly.dev/showcase/update_config')
end

# ... existing update logic ...

# Modify attempt_update to skip Fly-Force-Instance-Id header for Kamal
def attempt_update(uri, machine_id, verbose, target)
  # ... existing http setup ...

  request = Net::HTTP::Post.new(uri.path)
  # Only add Fly header for Fly.io targets
  request['Fly-Force-Instance-Id'] = machine_id if target == :fly

  # ... rest of method ...
end

# Update call sites to pass target
result = attempt_update(uri, machine_id, options[:verbose], options[:target])
```

**Benefits:**
- ✅ No changes to Fly.io behavior (default target)
- ✅ Clean separation between Fly and Kamal targets
- ✅ Reuses existing retry logic and error handling
- ✅ Works with existing CGI endpoint on showcase.party

### Phase 2: Update ShowcasesController Redirect

**File:** `app/controllers/showcases_controller.rb`

**Changes to lines 135-141:**

```ruby
# Determine redirect base URL based on environment
base_url = if Rails.env.development?
  "https://showcase.party"
else
  "/showcase"  # Relative URL for production (smooth.fly.dev)
end

@return_to = if events_this_year == 1
  # Single event: /:year/:location_key (or /showcase/:year/:location_key on Fly)
  "#{base_url}/#{@showcase.year}/#{@location_key}"
else
  # Multiple events: /:year/:location_key/:event_key
  "#{base_url}/#{@showcase.year}/#{@location_key}/#{@showcase.key}"
end
```

**Why this works:**
- ✅ Development: Redirects to `https://showcase.party/:year/:location` (no `/showcase` prefix)
- ✅ Production: Redirects to `/showcase/:year/:location` (relative URL, stays on smooth.fly.dev)
- ✅ Matches URL structure of each platform (Kamal has no scope, Fly has `/showcase` scope)

### Phase 3: Pass Target to ConfigUpdateJob (Optional)

**File:** `app/jobs/config_update_job.rb`

**Optional enhancement if you want to control target from Rails:**

```ruby
def perform(user_id, target: 'fly')
  # ... existing code ...

  # Pass target flag to script
  cmd = if target == 'kamal'
    "#{rails_root}/script/config-update --target kamal"
  else
    "#{rails_root}/script/config-update"
  end

  # ... existing execution code ...
end
```

**Update ShowcasesController call (line 119):**

```ruby
if user && Rails.env.production?
  ConfigUpdateJob.perform_later(user.id)
elsif user && Rails.env.development?
  ConfigUpdateJob.perform_later(user.id, target: 'kamal')
end
```

**Note:** This is optional. You could also just rely on the default behavior and manually run `script/config-update --target kamal` when testing.

## Testing Workflow

### Development Testing Flow

1. **Start Rails development server**
   ```bash
   bin/dev
   # or: RAILS_APP_DB=index bin/rails server
   ```

2. **Submit showcase request via web UI**
   - Navigate to new showcase request form
   - Fill out showcase details
   - Submit form

3. **Watch progress bar**
   - Progress page shows real-time updates
   - ConfigUpdateJob runs with `target: 'kamal'`
   - script/config-update posts to showcase.party CGI endpoint

4. **Automatic redirect**
   - Redirects to `https://showcase.party/:year/:location`
   - Showcase is live on backup server
   - No impact to smooth.fly.dev production

5. **Verify on backup**
   - Check showcase.party shows new event
   - Check prerender completed
   - Check Navigator config updated

### Manual Testing (Without ConfigUpdateJob)

If you want to test just the config-update script:

```bash
# From development machine (with index.sqlite3 updated)
script/sync_databases_s3.rb --index-only
script/config-update --target kamal --verbose

# Verify on backup server
curl https://showcase.party/update_config -X POST
ssh root@65.109.81.136 'ls -la /home/rubys/db/index.sqlite3'
```

## Additional Considerations

### 1. S3 Sync Still Goes to Production Bucket

**Issue:** `script/sync_databases_s3.rb` syncs to production S3 bucket, which Fly machines also fetch from.

**Options:**
- **A. Accept it:** Backup server pulling from same S3 is fine, changes are non-breaking
- **B. Separate buckets:** Add `--bucket` flag to sync script for dev testing
- **C. Skip S3 sync:** Add `--skip-s3` flag for pure local testing

**Recommendation:** Accept it (Option A). The index.sqlite3 is already in production S3, and backup server fetching it is harmless. The showcase won't appear on Fly until you actually run config-update against Fly machines.

### 2. CGI Endpoint Must Exist on Kamal Server

**Current State:** CGI endpoint `/update_config` is defined in Navigator config (both Fly and Kamal use same config).

**Verification Needed:**
- Ensure `config/navigator.yml` includes CGI endpoint (should already be there)
- Ensure endpoint is accessible on showcase.party
- Test: `curl -X POST https://showcase.party/update_config`

**If missing:** Add to `app/controllers/concerns/configurator.rb` CGI scripts section (already exists in production).

### 3. Authentication for CGI Endpoint

**Current:** CGI endpoints may require authentication depending on config.

**Check:** Does `/update_config` bypass auth? (It should for server-to-server calls)

**If needed:** Add to auth exclusions in configurator.rb:
```ruby
config['auth']['exclude_patterns'] ||= []
config['auth']['exclude_patterns'] << '^/update_config$'
```

### 4. Development Database vs Production Database

**Current Behavior:**
- Development: Uses `db/development.sqlite3` by default
- For testing: Need to use `RAILS_APP_DB=index` to access production index

**Recommendation:**
```bash
# Start development server with index database
RAILS_APP_DB=index bin/rails server

# Or add to .env.development:
RAILS_APP_DB=index
```

## Summary

### ✅ Feasible Changes Required

1. **script/config-update** - Add `--target` flag (20 lines)
   - Accept `--target fly|kamal` option
   - Skip Fly machine discovery for Kamal
   - Use showcase.party URL for Kamal
   - Skip Fly-Force-Instance-Id header for Kamal

2. **ShowcasesController** - Environment-aware redirect (5 lines)
   - Check `Rails.env.development?`
   - Use `showcase.party` base URL in dev
   - Use `/showcase` relative URL in production

3. **Optional: ConfigUpdateJob** - Target parameter (10 lines)
   - Accept `target:` keyword argument
   - Pass to script/config-update via flag
   - Default to `fly`

### ✅ No Other Changes Required

- ✅ CGI endpoint already exists on both platforms
- ✅ Unified Dockerfile already supports both platforms
- ✅ S3 sync can remain shared (or add flag if needed)
- ✅ Authentication exclusions already configured
- ✅ Progress bar already works with WebSocket

### Testing Impact

- ✅ Zero impact to production Fly.io operations
- ✅ Backup server updates in isolation
- ✅ Real end-to-end testing of showcase request flow
- ✅ Same user experience as production (progress bar, redirect)
- ✅ No need for manual deployment or config changes

## Bonus: Fix Output Buffering Issue

### Problem

ConfigUpdateJob reads script output via `Open3.popen3` and `stdout.each_line`, but Ruby buffers stdout by default. This causes progress updates to arrive in large chunks instead of line-by-line:

- User sees: "10% complete" → long wait → "100% complete"
- Should see: "10%" → "30%" → "40%" → "50%" → ... → "100%"

### Solution 1: Flush stdout in script (Simpler)

**File:** `script/config-update`

Add `$stdout.sync = true` at the top of the script (after shebang):

```ruby
#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'json'
require 'open3'
require 'optparse'

# Disable output buffering for real-time progress updates
$stdout.sync = true

# ... rest of script
```

**Why this works:**
- `$stdout.sync = true` disables buffering on stdout
- Every `puts` immediately writes to the pipe
- ConfigUpdateJob sees each line as soon as it's printed
- Minimal change (1 line)

### Solution 2: Use PTY in ConfigUpdateJob (More Robust)

**File:** `app/jobs/config_update_job.rb`

Replace `Open3.popen3` with `PTY.spawn` which provides unbuffered output:

```ruby
require 'open3'
require 'pty'
require 'io/console'

class ConfigUpdateJob < ApplicationJob
  def perform(user_id = nil)
    # ... existing setup ...

    script_path = Rails.root.join('script/config-update').to_s

    # Use PTY for unbuffered output
    begin
      PTY.spawn(RbConfig.ruby, script_path) do |stdout, stdin, pid|
        stdin.close

        machine_count = 0
        machines_updated = 0

        begin
          stdout.each_line do |line|
            line.chomp!
            Rails.logger.info "ConfigUpdateJob: #{line}"

            # Parse progress from output (same logic as before)
            if line.include?('Step 1: Syncing index database')
              broadcast(user_id, database, 'processing', 10, 'Syncing index database...')
            elsif line =~ /Will update (\d+) active machines/
              machine_count = $1.to_i
              broadcast(user_id, database, 'processing', 30, "Found #{machine_count} machines to update...")
            elsif line.include?('Step 3: Triggering configuration update')
              broadcast(user_id, database, 'processing', 40, 'Updating machines...')
            elsif line =~ /^\s+\S+\.\.\. ✓ Success/
              machines_updated += 1
              if machine_count > 0
                progress = 40 + (machines_updated.to_f / machine_count * 50).to_i
                broadcast(user_id, database, 'processing', progress, "Updated #{machines_updated}/#{machine_count} machines...")
              end
            end
          end
        rescue Errno::EIO
          # PTY raises EIO when child process exits - this is normal
        end

        Process.wait(pid)
        status = $?

        if status.success?
          # ... existing success handling ...
          broadcast(user_id, database, 'completed', 100, 'Configuration update complete!')
        else
          Rails.logger.error "ConfigUpdateJob: Failed with exit code #{status.exitstatus}"
          broadcast(user_id, database, 'error', 0, 'Configuration update failed')
          raise "Configuration update failed with exit code #{status.exitstatus}"
        end
      end
    rescue PTY::ChildExited => e
      Rails.logger.error "ConfigUpdateJob: Child process exited unexpectedly: #{e.message}"
      broadcast(user_id, database, 'error', 0, 'Configuration update failed')
      raise
    end
  end

  # ... rest of class
end
```

**Why this works:**
- PTY (pseudo-terminal) emulates a terminal device
- Programs connected to terminals typically use line-buffered output
- No buffering delays between script output and job reading
- More robust than relying on script to disable buffering

**Trade-offs:**
- PTY is more complex (exception handling for EIO)
- PTY might not be available on all platforms (Windows)
- Script solution is simpler and works everywhere

### Recommendation

**Use Solution 1 (`$stdout.sync = true`):**
- ✅ Simpler (1 line change)
- ✅ Works on all platforms
- ✅ No complex exception handling
- ✅ Clear intent (explicitly disable buffering)
- ✅ Job code stays simple

Only consider Solution 2 if you need PTY for other reasons (e.g., handling terminal control sequences).

## Next Steps

1. Fix output buffering: Add `$stdout.sync = true` to script/config-update
2. Implement `--target` flag in script/config-update
3. Update ShowcasesController redirect logic
4. Optional: Add target parameter to ConfigUpdateJob
5. Test showcase request from development against showcase.party
6. Verify progress bar updates in real-time (no buffering)
7. Verify redirect to showcase.party works
8. Document dev testing workflow in CLAUDE.md
