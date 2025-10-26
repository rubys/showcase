# CGI-Based Configuration Update Plan

## Overview

Replace heavyweight redeployment process with intelligent CGI script for configuration updates. This eliminates downtime and reduces update time from 3-5 minutes to seconds for common operations.

**Current State:**
- Every configuration change requires full redeployment
- Deployment triggers: sync DB, update htpasswd, prerender, generate navigator config
- Process takes 3-5 minutes with brief downtime
- `event#index_update` route provides limited workaround (sync + htpasswd only)

**Target State:**
- Single CGI script handles all configuration updates
- Fetches index.sqlite3 from Tigris/S3
- Always regenerates all configurations (htpasswd, maps, nav config)
- CGI completes in <5 seconds with zero downtime
- Navigator auto-reloads when navigator.yml changes
- Post-reload hook runs optimizations (prerender, database downloads) asynchronously

**Update Flow (Multi-Machine):**
```
User clicks "Update Configuration" (on any machine)
  ↓
Rails admin controller:
  1. Sync index.sqlite3 to S3 (if changed)
  2. Get list of ALL active Fly machines
  3. POST to /showcase/update_config on EACH machine
     (with Fly-Force-Instance-Id header to target specific machine)
  ↓
Each machine's CGI script executes (in parallel):
  1. Fetch index.sqlite3 from S3
  2. Update htpasswd
  3. Update region maps
  4. Update navigator.yml
  5. Return success (<5 sec per machine)
  ↓
Each machine's Navigator detects navigator.yml changed
  ↓
Each Navigator reloads configuration (new config active on all machines)
  ↓
Each Navigator runs ready hooks in background:
  1. Prerender static HTML (10-30 sec)
  2. Download/migrate event databases
  ↓
All machines updated (zero downtime)
```

**Key Pattern:**
- **One machine** uploads index.sqlite3 to S3
- **All active machines** fetch from S3 and update their configs
- Uses existing `Fly-Force-Instance-Id` header for targeting
- Parallel execution across all machines (faster than serial)

---

## Prerequisites

### ✅ Completed

1. **Navigator CGI Support** (v0.16.0)
   - User switching capability (run as rails user)
   - Access control via `allowed_users`
   - Smart configuration reload (only when modified during execution)
   - Environment variable inheritance (AWS credentials available)
   - Timeout support for long-running operations
   - Standard CGI/1.1 protocol implementation

### ⏳ Required (Not Yet Implemented)

2. **Navigator Ready Hook Extension** (v0.17.0 or later)
   - Extend `ready` hook to run **both** on initial start AND after config reloads
   - Currently `ready` only runs after initial start
   - After change, `ready` runs: initial start, CGI reload, resume reload, SIGHUP reload
   - Runs while Navigator continues serving requests (non-blocking)
   - Used for optimizations that don't affect correctness (prerender, DB downloads)

   **Current behavior:**
   ```
   start hook → Navigator starts → ready hook (once)
   ```

   **New behavior:**
   ```
   start hook → Navigator starts → ready hook (initial)

   Config reload (CGI/SIGHUP/resume) → ready hook (again)
   ```

   **Configuration format (no changes needed):**
   ```yaml
   hooks:
     server:
       ready:
         - command: /rails/script/post_reload.sh
           timeout: 10m
   ```

   **Why this is required:**
   - Prerender can take 10-30 seconds or more
   - CGI timeout is 10 minutes, but we want fast feedback
   - Config updates should complete in seconds, not wait for prerender
   - Prerender is optimization only (pages work without it)

   **Execution flow:**
   1. CGI script updates config files (htpasswd, maps, navigator.yml)
   2. CGI script returns success response (fast, <5 seconds)
   3. Navigator detects navigator.yml changed → reloads config
   4. **Navigator runs ready hooks** (same as initial start)
   5. Ready hook runs prerender, downloads event databases

   **Semantics clarification:**
   - `start` = Navigator is starting up (before listening)
   - `ready` = Navigator is ready to serve (initial OR after reload)
   - `idle` = About to suspend/stop
   - `resume` = Resuming from suspend
   - `stop` = Shutting down

   **Implementation:**
   - Modify reload logic in Navigator to execute ready hooks
   - No new hook type needed
   - Cleaner semantics ("ready to serve" = initial + reloads)

   **Documentation updates needed:**
   - `navigator/docs/features/lifecycle-hooks.md`:
     - Update `ready` hook description: "After Navigator starts listening **or after configuration reload**"
     - Add to "When Executed" column: "initial start, config reload (CGI, SIGHUP, resume)"
     - Add example: Using ready hook for cache warming after config updates
   - `navigator/docs/configuration/yaml-reference.md`:
     - Update `hooks.server.ready` description to include reload behavior
   - `navigator/CLAUDE.md`:
     - Update lifecycle hooks section with new ready hook behavior
     - Add to "Configuration Reload" section about ready hooks running

   **Status:** ⏳ Needs to be implemented in Navigator

   **Issue:** Track at https://github.com/rubys/navigator/issues/

---

## Phase 1: CGI Script Foundation

### 1.1 Create Smart Configuration Script

**File:** `script/update_configuration.rb`

**Requirements:**
```ruby
#!/usr/bin/env ruby
# CGI script for intelligent configuration updates
# Fetches index DB from S3, detects changes, performs necessary operations

require 'bundler/setup'
require 'fileutils'
require 'json'
require 'yaml'
require_relative '../lib/htpasswd_updater'

# CGI response helpers
def cgi_header(content_type = 'text/plain')
  puts "Content-Type: #{content_type}"
  puts ""
end

def log(message)
  puts "[#{Time.now.iso8601}] #{message}"
  STDOUT.flush
end

# Main execution
cgi_header
log "Starting configuration update..."
```

**Core Functionality:**
- Fetch index.sqlite3 from Tigris/S3
- Always regenerate fast configurations (htpasswd, maps, navigator config)
- Return detailed status report in <5 seconds
- Trigger Navigator config reload
- Navigator runs post-reload hook for optimizations (prerender, event DB downloads)

**CGI Operations (fast, synchronous):**
1. **Database sync** - Always fetch latest index from S3
2. **htpasswd update** - Always regenerate (fast, ~1 sec)
3. **Region map generation** - Always regenerate (fast, ~1 sec)
4. **Navigator config** - Always regenerate (fast, ~1 sec)
5. **Return success** - CGI completes, Navigator will reload config

**Post-Reload Operations (slow, asynchronous via hook):**
6. **Prerender** - Regenerate all static HTML (10-30 seconds)
7. **Event databases** - Download/migrate event databases (varies)

### 1.2 Add Navigator CGI Configuration

**File:** Update `config/navigator.yml` (or via nav:config task)

```yaml
server:
  cgi_scripts:
    - path: /showcase/update_config
      script: /rails/script/update_configuration.rb
      method: POST
      user: rails
      group: rails
      allowed_users:
        - admin
      timeout: 5m  # Fast timeout (just config updates, not prerender)
      reload_config: config/navigator.yml
      env:
        RAILS_DB_VOLUME: /data/db
        RAILS_ENV: production

hooks:
  server:
    ready:
      - command: /rails/script/post_reload.sh
        timeout: 10m
        # Runs on initial start AND after config reloads
```

**Status:** ⏳ Not started

**Dependencies:** Navigator ready hook extension (see Prerequisites)

---

## Phase 2: Always-Generate Strategy

### 2.1 All Operations Always Run

**Rationale:**
- Prerender is an **optimization**, not required for correctness
- Without it, pages would be served dynamically by index tenant
- Detection logic adds complexity and risk of false negatives
- All operations are fast enough to always run
- File system/Navigator handles actual change detection

**CGI Operations (Always Run, Fast <5 seconds):**
1. **Database sync** - Always fetch latest index.sqlite3 from S3
2. **htpasswd update** (~1 second) - Always regenerate from index database
3. **Navigator config** (~1 second) - Always regenerate from index database
4. **Region maps** (~1 second) - Always regenerate from index database

**Post-Reload Hook Operations (Run after Navigator reloads):**
5. **Prerender** - Regenerate static HTML from index database
6. **Event databases** - Download/update event databases via bin/prepare.rb

**Separation Rationale:**
- CGI completes fast (<5 sec) → fast user feedback
- Navigator reloads config immediately → new config active
- Post-reload hook runs optimizations in background → zero downtime
- Prerender based on index.sqlite3 directly (migrate away from showcases.yml/tenants.list)

**Status:** ⏳ Not started

### 2.2 Architectural Direction: Index Database as Source of Truth

**Current State:**
- `showcases.yml` generated from index database (intermediate file)
- `tenants.list` generated from showcases.yml (another intermediate)
- Prerender reads showcases.yml to determine what to render
- Navigator config generated from showcases.yml

**Target State:**
- Prerender reads index.sqlite3 directly
- Navigator config generated from index.sqlite3 directly
- Retire showcases.yml and tenants.list
- Index database is single source of truth

**Benefits:**
- Fewer intermediate files to maintain
- No sync issues between index DB and derived files
- Simpler architecture
- Easier to understand data flow

**Status:** ⏳ Future enhancement (post-MVP)

---

## Phase 3: Operation Implementations

### 3.1 CGI Script Operations (Fast)

**Operations to integrate into update_configuration.rb:**

1. **Database sync** - `script/sync_databases_s3.rb --index-only`
   - Already works, use as-is
   - Downloads index.sqlite3 from S3
   - Returns status and output

2. **htpasswd update** - `User.update_htpasswd` (from event#index_update)
   - Already works, use as-is
   - Fast operation (~1 second)
   - Generates htpasswd from index database users table

3. **Navigator config** - `bin/rails nav:config`
   - Already works, use as-is
   - Currently generates from showcases.yml
   - Future: generate from index.sqlite3 directly
   - Generates config/navigator.yml

4. **Map generation** - Extract from `admin#destroy_region`, `admin#create_region`
   - Current: `generate_map` method
   - Make standalone/callable
   - Generates config/tenant/map.yml

**Status:** ⏳ Not started

**Priority:**
1. Database sync (already works)
2. htpasswd update (already works)
3. Navigator config generation (already works)
4. Map generation (needs extraction - may already be callable)

### 3.2 Ready Hook Script (Post-Reload Operations)

**File:** `script/post_reload.sh`

Once Navigator extends the ready hook to run on config reloads (see Prerequisites), this script will be called after initial start AND after configuration reloads.

**Script responsibilities:**
```bash
#!/bin/bash
# Post-reload optimization script
# Runs AFTER Navigator has reloaded config and is serving requests

set -e

log() {
  echo "[$(date -Iseconds)] $@"
}

log "Starting post-reload optimizations..."

# 1. Run prerender (regenerate static HTML)
log "Running prerender..."
cd /rails
RAILS_ENV=production bin/prerender

# 2. Download/update event databases
log "Updating event databases..."
if [ -f "tmp/tenants.list" ]; then
  while IFS= read -r db_path; do
    ruby bin/prepare.rb "$db_path"
  done < tmp/tenants.list
fi

log "Post-reload optimizations complete"
```

**Benefits:**
- CGI script completes in <5 seconds (just config updates)
- Prerender runs in background (zero perceived downtime)
- Event databases download while Navigator serves with new config
- Clean separation of concerns (critical vs optimization)
- Same script runs on initial start AND reloads (consistent behavior)

**Status:** ⏳ Blocked on Navigator ready hook extension

---

## Phase 4: Replace admin#apply with CGI-Based Updates

### 4.1 Understanding Current admin#apply Implementation

**Current workflow:**
1. User visits `/admin/apply` which calls `admin#apply` action
2. Action generates `db/showcases.yml` from index.sqlite3
3. Compares with `config/tenant/showcases.yml` to detect changes
4. Displays changes preview page with submit button
5. Submit button triggers OutputChannel via WebSocket
6. Background job executes deployment commands
7. Real-time output displayed via xterm terminal

**Current operations (from OutputChannel command):**
- `rsync` database to production server
- `fly regions add/delete` for region changes
- `fly deploy` for code changes and configuration updates
- Real-time streaming output to browser terminal

**Current change detection:**
- Database sync: Uses `rsync --dry-run` to check if index.sqlite3 changed
- Region additions: From `@pending['add']`
- Region deletions: From `@pending['delete']`
- Site moves: Comparing region assignments in showcases.yml
- Showcase changes: Comparing event lists in showcases.yml
- Code changes: `git status --short`

### 4.2 New CGI-Based Approach

**Replace deployment with targeted CGI updates:**

The CGI script replaces most of the deployment workflow:
- ✅ Database sync: CGI fetches from S3 directly (no rsync needed)
- ✅ Configuration updates: CGI generates navigator.yml and triggers reload
- ✅ htpasswd updates: CGI updates from index database
- ✅ Map regeneration: CGI generates region maps
- ✅ Prerendering: CGI prerenders changed events only
- ❌ Code deployment: Still requires `fly deploy` (unchanged)
- ❌ Region add/delete: Still requires `fly regions` commands (unchanged)

### 4.3 Update admin#apply Page

**Keep existing preview page but change what "submit" does:**

**Modified view:** `app/views/admin/apply.html.erb`

```erb
<!-- After showing all changes... -->

<% if changes %>
  <% if @pending['add'].present? || @pending['delete'].present? || code_changes_present %>
    <!-- Original deployment flow for region/code changes -->
    <h3 class="text-xl font-bold mt-6">Full Deployment Required</h3>
    <p class="text-sm text-gray-600 mb-2">Region or code changes require deployment</p>

    <button data-submit-target="submit" data-stream="<%= @stream %>"
      class="flex mx-auto bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 border-2 rounded-xl my-4 disabled:opacity-50 disabled:cursor-not-allowed">
      Deploy Changes
    </button>
  <% else %>
    <!-- New CGI-based configuration update -->
    <h3 class="text-xl font-bold mt-6">Configuration Update</h3>
    <p class="text-sm text-gray-600 mb-2">Fast update via CGI (no deployment needed)</p>

    <%= button_to "Update Configuration",
                  trigger_config_update_admin_path,
                  method: :post,
                  class: "flex mx-auto bg-green-500 hover:bg-green-700 text-white font-bold py-2 px-4 border-2 rounded-xl my-4",
                  data: {
                    turbo_stream: true,
                    controller: "config-update",
                    action: "click->config-update#execute"
                  } %>
  <% end %>
<% end %>

<!-- Terminal output area (used by both flows) -->
<div class="hidden p-4 bg-black rounded-xl">
  <div data-submit-target="output" data-stream="<%= @stream %>"
    class="w-full mx-auto overflow-y-auto h-auto font-mono text-sm max-h-[25rem] min-h-[25rem]">
  </div>
</div>
```

**Status:** ⏳ Not started

### 4.4 Add Controller Actions

**Add to `admin_controller.rb`:**

```ruby
def trigger_config_update
  # Set up streaming output
  @stream = OutputChannel.register(:config_update)

  Thread.new do
    begin
      OutputChannel.send(@stream, "Starting configuration update...\n\n")

      # Step 1: Sync index.sqlite3 to S3 (if changed)
      OutputChannel.send(@stream, "Step 1: Syncing index database to S3...\n")
      OutputChannel.send(@stream, "=" * 50 + "\n")

      script_path = Rails.root.join('script', 'sync_databases_s3.rb')
      stdout, stderr, status = Open3.capture3('ruby', script_path.to_s, '--index-only')

      OutputChannel.send(@stream, stdout)
      OutputChannel.send(@stream, stderr) unless stderr.empty?

      unless status.success?
        OutputChannel.send(@stream, "\n❌ Index sync failed\n")
        OutputChannel.send(@stream, "\u0004")
        next
      end

      OutputChannel.send(@stream, "\n")

      # Step 2: Get list of active Fly machines
      OutputChannel.send(@stream, "Step 2: Getting list of active Fly machines...\n")
      OutputChannel.send(@stream, "=" * 50 + "\n")

      flyctl = ENV['FLY_CLI_PATH'] || File.expand_path('~/bin/flyctl')
      machines_output, _, status = Open3.capture3(flyctl, 'machines', 'list', '--json')

      unless status.success?
        OutputChannel.send(@stream, "❌ Failed to get machines list\n")
        OutputChannel.send(@stream, "\u0004")
        next
      end

      machines = JSON.parse(machines_output)
      active_machines = machines.select { |m| ['started', 'created'].include?(m['state']) }
      machine_ids = active_machines.map { |m| m['id'] }

      OutputChannel.send(@stream, "Found #{machines.length} total machines\n")
      OutputChannel.send(@stream, "Will update #{machine_ids.length} active machines\n\n")

      if machine_ids.empty?
        OutputChannel.send(@stream, "No active machines to update\n")
        OutputChannel.send(@stream, "\u0004")
        next
      end

      # Step 3: Call CGI endpoint on each machine
      OutputChannel.send(@stream, "Step 3: Updating configuration on each machine...\n")
      OutputChannel.send(@stream, "=" * 50 + "\n")

      success_count = 0
      failure_count = 0

      machine_ids.each do |machine_id|
        OutputChannel.send(@stream, "  #{machine_id}... ")

        begin
          uri = URI("https://#{request.host}/showcase/update_config")

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.read_timeout = 300  # 5 minute timeout for CGI
          http.open_timeout = 10

          req = Net::HTTP::Post.new(uri.path)
          req['Fly-Force-Instance-Id'] = machine_id  # Target specific machine

          # Pass through authentication
          if request.authorization
            req['Authorization'] = request.authorization
          elsif current_user
            req.basic_auth(current_user.username, session[:password])
          end

          response = http.request(req)

          if response.code == '200'
            OutputChannel.send(@stream, "✓ Success\n")
            success_count += 1
          else
            OutputChannel.send(@stream, "✗ Failed (HTTP #{response.code})\n")
            failure_count += 1
          end

        rescue => e
          OutputChannel.send(@stream, "✗ Error: #{e.message}\n")
          failure_count += 1
        end
      end

      # Summary
      OutputChannel.send(@stream, "\n")
      OutputChannel.send(@stream, "Summary:\n")
      OutputChannel.send(@stream, "=" * 50 + "\n")
      OutputChannel.send(@stream, "Successfully updated: #{success_count} machines\n")
      OutputChannel.send(@stream, "Failed updates: #{failure_count} machines\n") if failure_count > 0

      if failure_count > 0
        OutputChannel.send(@stream, "\n❌ Configuration update completed with errors\n")
      else
        OutputChannel.send(@stream, "\n✅ Configuration update completed successfully\n")
      end

    rescue => e
      OutputChannel.send(@stream, "\n❌ Error: #{e.message}\n")
      OutputChannel.send(@stream, e.backtrace.join("\n") + "\n")
    ensure
      OutputChannel.send(@stream, "\u0004") # Send EOT
    end
  end

  head :ok
end
```

**Implementation Notes:**
- Similar pattern to `script/user-update` (broadcast to all machines)
- Uses `Fly-Force-Instance-Id` header to target each machine
- Syncs index.sqlite3 to S3 once, then each machine fetches it
- Real-time streaming output via OutputChannel
- Runs in background thread to not block response

**Status:** ⏳ Not started

### 4.5 Add Routes

**Update `config/routes.rb`:**

```ruby
namespace :admin do
  # ... existing routes ...
  get 'apply' => 'admin#apply'
  post 'trigger_config_update' => 'admin#trigger_config_update'
end
```

**Status:** ⏳ Not started

### 4.6 Optional: Direct CGI Stream

**Alternative approach - stream directly from CGI to browser:**

Instead of proxying through Rails controller, could use EventSource or WebSocket to connect directly to CGI script output. This would require:

1. CGI script outputs Server-Sent Events format
2. JavaScript EventSource connects to CGI endpoint
3. Real-time streaming without Rails middleware

**Pros:**
- Direct connection to CGI (no Rails proxy)
- Lower latency for output
- Less memory usage

**Cons:**
- More complex JavaScript
- Different pattern from existing admin#apply
- Browser compatibility considerations

**Decision:** Start with Rails proxy approach (simpler, matches existing pattern). Consider direct streaming as future optimization if needed.

**Status:** ⏳ Future consideration

---

## Phase 5: Migration and Testing

### 5.1 Test in Development

**Steps:**
1. Create test index database with known changes
2. Run CGI script manually
3. Verify change detection logic
4. Confirm operations execute correctly
5. Check navigator config reload works

**Status:** ⏳ Not started

### 5.2 Deploy to Production

**Deployment steps:**
1. Deploy updated application code with CGI script
2. Update navigator.yml with CGI configuration
3. Restart navigator to load CGI config
4. Test with non-critical change
5. Monitor logs for issues
6. Document any edge cases discovered

**Status:** ⏳ Not started

### 5.3 Replace script/user-update

**Current usage of script/user-update:**

The script is called from 3 locations:
1. `bin/apply-changes.rb` - When remote index is older than local
2. `users_controller.rb#update_htpasswd_everywhere` - When user changes
3. `locations_controller.rb#update` - When trust_level changes

**What script/user-update does:**
```ruby
# Old approach (script/user-update calls script/sync_databases_s3.rb):
1. Sync index.sqlite3 to S3
2. Get list of ALL active Fly machines (via flyctl)
3. POST to /showcase/index_update on each machine
4. Each machine downloads index and updates htpasswd
```

**Replacement strategy:**

Create a unified helper method in ApplicationController:

```ruby
def trigger_config_update_async
  return unless Rails.env.production?

  ConfigUpdateJob.perform_later
end
```

**Replace the 3 call sites:**

```ruby
# users_controller.rb
def update_htpasswd_everywhere
  User.update_htpasswd
  trigger_config_update_async if Rails.env.production?
end

# locations_controller.rb
def update
  if @location.update(location_params)
    generate_showcases
    generate_map
    trigger_config_update_async if trust_level_changed?
  end
end

# bin/apply-changes.rb
# Call admin#trigger_config_update instead of script/user-update
```

**ConfigUpdateJob implementation:**

```ruby
class ConfigUpdateJob < ApplicationJob
  def perform
    # Same logic as admin#trigger_config_update
    # 1. Sync to S3
    # 2. Get machines
    # 3. Broadcast to CGI endpoints
  end
end
```

**Benefits of replacing:**
- ✅ Single code path (don't maintain two broadcast mechanisms)
- ✅ More complete (updates maps, navigator config, prerender)
- ✅ Faster (parallel CGI with async prerender)
- ✅ Cleaner (no script spawning, proper error handling)
- ✅ Consistent (same mechanism for all config updates)

**Migration steps:**
1. Implement ConfigUpdateJob with same broadcast logic
2. Replace spawn calls with ConfigUpdateJob.perform_later
3. Test each call site (users, locations, apply-changes)
4. Deprecate script/user-update with warning
5. Remove script/user-update after stable period

**Status:** ⏳ Not started (do after CGI implementation proven)

### 5.4 Deprecate Old Routes

**Once CGI script is proven:**
1. Keep `event#index_update` for backward compatibility initially
2. Update internal processes to use CGI endpoint
3. Document new workflow in README
4. Add deprecation notice to old route
5. Remove after transition period

**Status:** ⏳ Not started

---

## Success Metrics

### Performance Targets

| Operation | Current | Target (Total) | Per-Machine CGI | Background (Post-Reload) | Actual |
|-----------|---------|----------------|-----------------|--------------------------|--------|
| Full deployment | 3-5 min | N/A | N/A | N/A | - |
| Password update | 3-5 min | <30 sec | <5 sec | +10-30 sec (prerender) | - |
| New event | 3-5 min | <30 sec | <5 sec | +10-30 sec (prerender) | - |
| New studio | 3-5 min | <30 sec | <5 sec | +10-30 sec (prerender) | - |
| Config only | 3-5 min | <30 sec | <5 sec | +10-30 sec (prerender) | - |

**Total Time Breakdown (for 8 active machines):**
- Upload index.sqlite3 to S3: ~5 sec
- Get machine list: ~2 sec
- Update all machines (parallel): ~5-10 sec (each machine fetches S3, updates configs)
- Background prerender on each machine: +10-30 sec (async, doesn't block)
- **Total user-facing time: ~15-20 seconds** (vs 3-5 minutes currently)

**Key Improvement:**
- All machines updated in parallel using `Fly-Force-Instance-Id` targeting
- CGI completes in <5 sec per machine (fast operations only)
- Prerender runs asynchronously via post-reload hook (zero perceived downtime)
- **10-15x faster** than current deployment-based approach

### Quality Targets

- ✅ Zero downtime during updates
- ✅ Detailed operation logging
- ✅ Rollback capability (old config preserved)
- ✅ Security maintained (admin-only access)
- ✅ Error handling and reporting

---

## Risk Mitigation

### Potential Issues

1. **CGI script fails mid-operation**
   - Mitigation: Atomic operations, backup current state
   - Recovery: Manual fix, then re-run script
   - Impact: Config may be partially updated, but Navigator still running

2. **Navigator config reload doesn't trigger**
   - Mitigation: Log reload decision clearly in Navigator
   - Recovery: Manual SIGHUP to navigator
   - Impact: Old config still active until reload

3. **Post-reload hook fails**
   - Mitigation: Hook failures don't affect Navigator operation
   - Recovery: Run prerender manually (bin/prerender)
   - Impact: Missing prerendered content, pages served dynamically (slower but functional)

4. **S3 fetch fails**
   - Mitigation: Keep current index, return error
   - Recovery: Retry when S3 is available
   - Impact: Configuration not updated

5. **Concurrent updates**
   - Mitigation: Single-threaded CGI script execution
   - Impact: Second request waits for first to complete (Navigator queues CGI requests)

6. **Post-reload hook still running when next update triggers**
   - Mitigation: Hook should check for lock file before running
   - Impact: May skip prerender if previous one still running
   - Acceptable: Prerender is optimization only

---

## Timeline

**Phase 0: Navigator Prerequisites** (2-4 hours)
- Extend ready hook to run on config reloads (not just initial start)
- Test ready hook executes after CGI reload, SIGHUP reload, resume reload
- Verify hook runs while Navigator serves requests (non-blocking)
- Update Navigator documentation (lifecycle-hooks.md, yaml-reference.md, CLAUDE.md)
- Release Navigator v0.17.0 or later

**Phase 1: Foundation** (2-3 hours)
- Create update_configuration.rb CGI script
- Create post_reload.sh ready hook script
- Add navigator CGI config and ready hook config
- Test basic CGI execution and ready hook triggering

**Phase 2: Operations Integration** (3-4 hours)
- Integrate database sync operation
- Integrate htpasswd update operation
- Integrate navigator config generation
- Extract/call map generation operation
- Test each operation independently

**Phase 3: UI Integration** (2-3 hours)
- Update admin#apply page to use CGI
- Add trigger_config_update controller action
- Implement real-time output display
- Test end-to-end from admin UI

**Phase 4: Testing & Deployment** (2-3 hours)
- End-to-end testing
- Production deployment
- Monitor first production run
- Documentation

**Total estimated time:** 13-19 hours (excluding Navigator prerequisite work)

---

## Future Enhancements

### Post-MVP Features

1. **Change Preview**
   - Show what will change before executing
   - Require confirmation for destructive changes
   - "Dry run" mode

2. **Operation History**
   - Log all configuration updates
   - Track what changed and when
   - Enable audit trail

3. **Webhook Support**
   - Trigger updates via webhook (GitHub, CI/CD)
   - Automatic updates on index database changes
   - Integration with external systems

4. **Index Database as Direct Source**
   - Prerender reads from index.sqlite3 directly (no showcases.yml)
   - Navigator config generated from index.sqlite3 directly
   - Retire showcases.yml and tenants.list intermediate files
   - Simpler architecture, fewer sync issues

---

## Decision Log

**2025-10-26 (Initial):**
- ✅ Decided to use CGI instead of Rails route for better isolation
- ✅ Selected 10-minute timeout as safe for longest operations

**2025-10-26 (Revised after discussion - always-generate approach):**
- ✅ **Changed to always-generate approach** instead of change detection
  - Rationale: Prerender is optimization, not required for correctness
  - Simpler code, less risk of false negatives
  - File system/Navigator handles actual change detection
- ✅ **Always run prerender** (don't skip based on detection)
  - Prerender already runs in script/nav_initialization.rb
  - Should be part of every config update
  - Moved to Navigator post-reload hook (prerequisite)
- ✅ **Architectural direction: index.sqlite3 as source of truth**
  - Migrate prerender to read from index database directly
  - Retire showcases.yml and tenants.list intermediate files
  - Simplifies data flow and reduces sync issues

**2025-10-26 (After reviewing admin#apply - multi-machine architecture):**
- ✅ **Multi-machine broadcast pattern identified**
  - Current: `script/user-update` broadcasts to all active machines via `Fly-Force-Instance-Id`
  - Each machine runs `index_update` endpoint to fetch S3 and update htpasswd
  - Pattern: One machine uploads to S3, all machines fetch and update
- ✅ **CGI must run on each active machine**
  - Admin controller syncs to S3, then POSTs to each machine's CGI endpoint
  - Similar to current `script/user-update` → `index_update` flow
  - Parallel execution across all machines (not just one)
- ✅ **Ready hook extension is prerequisite, not future**
  - Without it, CGI blocks on prerender (30+ seconds × N machines)
  - With it, CGI completes in <5 sec, prerender runs async via ready hook
  - Essential for performance target (<30 sec total)
- ✅ **script/user-update can be replaced entirely**
  - Currently used in 3 places: bin/apply-changes.rb, users_controller.rb, locations_controller.rb
  - Does partial update: sync index + update htpasswd only
  - CGI approach is superset: sync index + htpasswd + maps + navigator config + prerender
  - Replace with ConfigUpdateJob.perform_later for cleaner, unified approach
  - Single code path eliminates maintenance of two broadcast mechanisms

**2025-10-26 (Simplified hook approach):**
- ✅ **Use ready hook instead of new reload hook**
  - Initial plan: Add new `reload` hook type that runs after config reloads
  - Simpler approach: Extend existing `ready` hook to run on reloads too
  - Cleaner semantics: "ready to serve" = initial start OR after reload
  - No new hook type needed in Navigator
  - Works for: initial start, CGI reload, SIGHUP reload, resume reload
- ✅ **Ready hook naturally fits "ready to serve" semantics**
  - `start` = before listening (setup tasks)
  - `ready` = ready to serve (initial + reloads)
  - `idle` = about to suspend/stop
  - `resume` = resuming from suspend
  - `stop` = shutting down

---

## References

- [Navigator CGI Documentation](https://rubys.github.io/navigator/features/cgi-scripts/)
- [CGI/1.1 Specification (RFC 3875)](https://www.rfc-editor.org/rfc/rfc3875.html)
- Blog post: "Bringing CGI Back from the Dead" (src/3379.md)
- Current implementation: `app/controllers/event_controller.rb#index_update`
- Initialization script: `script/nav_initialization.rb`
