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
- Detects what changed and performs only necessary operations
- Updates complete in 10-30 seconds with zero downtime
- Navigator auto-reloads configuration when needed

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
- Compare with current index (if exists)
- Detect changes:
  - New/removed studio locations
  - New/removed events
  - Password changes (user table)
  - Region assignments
- Perform only necessary operations
- Generate new navigator config if needed
- Return detailed status report

**Operations to support:**
1. **Database sync** - Always fetch latest index
2. **htpasswd update** - If users changed
3. **Region map generation** - If studios/regions changed
4. **Index prerender** - If events added/changed
5. **Navigator config** - If showcases.yml needs updates

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
      timeout: 10m
      reload_config: config/navigator.yml
      env:
        RAILS_DB_VOLUME: /data/db
        RAILS_ENV: production
```

**Status:** ⏳ Not started

**Dependencies:** None (Navigator v0.16.0 already deployed)

---

## Phase 2: Change Detection Logic

### 2.1 Implement Database Comparison

**Module:** `lib/configuration_detector.rb`

**Key Methods:**
```ruby
class ConfigurationDetector
  def initialize(current_db_path, new_db_path)
    @current_db = current_db_path
    @new_db = new_db_path
  end

  def detect_changes
    {
      studios_changed: studios_changed?,
      events_changed: events_changed?,
      passwords_changed: passwords_changed?,
      regions_changed: regions_changed?,
      showcases_changed: showcases_changed?
    }
  end

  private

  def studios_changed?
    # Compare studio records between databases
  end

  def events_changed?
    # Compare showcase/event records
  end

  def passwords_changed?
    # Compare user table hashes
  end

  def regions_changed?
    # Compare region assignments in showcases.yml
  end
end
```

**Status:** ⏳ Not started

**Testing Requirements:**
- Unit tests for each change detection method
- Integration tests with sample database changes
- Edge cases: first run (no current DB), empty databases

### 2.2 Operation Mapping

**Map changes to required operations:**

```ruby
OPERATION_MAP = {
  studios_changed: [:update_htpasswd, :regenerate_maps, :regenerate_nav_config],
  events_changed: [:prerender_indexes, :regenerate_nav_config],
  passwords_changed: [:update_htpasswd],
  regions_changed: [:regenerate_maps, :regenerate_nav_config],
  showcases_changed: [:regenerate_nav_config]
}
```

**Status:** ⏳ Not started

---

## Phase 3: Operation Implementations

### 3.1 Extract Reusable Operations

**From existing scripts:**

1. **Database sync** - `script/sync_databases_s3.rb --index-only`
   - Already works, use as-is
   - Returns status and output

2. **htpasswd update** - `User.update_htpasswd` (from event#index_update)
   - Already works, use as-is
   - Fast operation (~1 second)

3. **Map generation** - Extract from `admin#destroy_region`, `admin#create_region`
   - Current: `generate_map` method
   - Make standalone/callable

4. **Prerender** - `bin/prerender`
   - Currently runs all events
   - Add selective prerender (specific events only)
   - Most time-consuming operation

5. **Navigator config** - `bin/rails nav:config`
   - Already works, use as-is
   - Generates full config from showcases.yml

**Status:** ⏳ Not started

**Priority:**
1. Database sync (already works)
2. htpasswd update (already works)
3. Navigator config generation (already works)
4. Map generation (needs extraction)
5. Selective prerender (needs implementation)

### 3.2 Selective Prerender

**Enhancement to `bin/prerender`:**

```ruby
# Current: Prerender all events
# New: Accept optional event list

if ARGV.empty?
  # Prerender all events (current behavior)
  events = Event.all
else
  # Prerender specific events by database name
  db_names = ARGV
  events = Event.where(database: db_names)
end
```

**Status:** ⏳ Not started

**Benefits:**
- Faster updates when only one event changed
- Reduces update time from minutes to seconds
- Backwards compatible (no args = all events)

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

  # Call CGI endpoint via HTTP (authenticated request)
  OutputChannel.send(@stream, "Triggering configuration update via CGI...\n")

  begin
    uri = URI("https://#{request.host}/showcase/update_config")
    req = Net::HTTP::Post.new(uri)

    # Pass through authentication
    if request.authorization
      req['Authorization'] = request.authorization
    elsif current_user
      req.basic_auth(current_user.username, session[:password])
    end

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.read_timeout = 600 # 10 minute timeout
      http.request(req)
    end

    # Stream the response
    OutputChannel.send(@stream, response.body)

    if response.code.to_i == 200
      OutputChannel.send(@stream, "\n✅ Configuration update completed successfully\n")
    else
      OutputChannel.send(@stream, "\n❌ Configuration update failed (HTTP #{response.code})\n")
    end

  rescue => e
    OutputChannel.send(@stream, "\n❌ Error: #{e.message}\n")
  ensure
    OutputChannel.send(@stream, "\u0004") # Send EOT
  end

  head :ok
end
```

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

### 5.3 Deprecate Old Routes

**Once CGI script is proven:**
1. Keep `event#index_update` for backward compatibility
2. Update internal processes to use CGI endpoint
3. Document new workflow in README
4. Add deprecation notice to old route

**Status:** ⏳ Not started

---

## Success Metrics

### Performance Targets

| Operation | Current | Target | Actual |
|-----------|---------|--------|--------|
| Full deployment | 3-5 min | N/A | - |
| Password update | 3-5 min | 5-10 sec | - |
| New event | 3-5 min | 20-30 sec | - |
| New studio | 3-5 min | 30-60 sec | - |
| Config only | 3-5 min | 5-10 sec | - |

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

2. **Navigator config reload doesn't trigger**
   - Mitigation: Log reload decision clearly
   - Recovery: Manual SIGHUP to navigator

3. **Prerender takes too long**
   - Mitigation: 10-minute timeout configured
   - Recovery: Run prerender manually if needed

4. **S3 fetch fails**
   - Mitigation: Keep current index, return error
   - Recovery: Retry when S3 is available

5. **Concurrent updates**
   - Mitigation: Single-threaded script execution
   - Impact: Second request waits for first to complete

---

## Timeline

**Phase 1: Foundation** (2-3 hours)
- Create update_configuration.rb skeleton
- Add navigator CGI config
- Test basic CGI execution

**Phase 2: Detection** (3-4 hours)
- Implement ConfigurationDetector
- Write unit tests
- Test with sample databases

**Phase 3: Operations** (4-6 hours)
- Extract map generation
- Implement selective prerender
- Integrate existing operations

**Phase 4: UI Integration** (2-3 hours)
- Add admin button
- Create controller action
- Implement output display

**Phase 5: Testing & Deployment** (2-3 hours)
- End-to-end testing
- Production deployment
- Documentation

**Total estimated time:** 13-19 hours

---

## Future Enhancements

### Post-MVP Features

1. **Incremental Updates**
   - Track last sync timestamp
   - Only process changes since last sync
   - Faster updates for frequent operations

2. **Change Preview**
   - Show what will change before executing
   - Require confirmation for destructive changes
   - "Dry run" mode

3. **Operation History**
   - Log all configuration updates
   - Track what changed and when
   - Enable audit trail

4. **Webhook Support**
   - Trigger updates via webhook (GitHub, CI/CD)
   - Automatic updates on index database changes
   - Integration with external systems

5. **Parallel Operations**
   - Run independent operations concurrently
   - Faster updates when multiple changes detected
   - Careful coordination required

---

## Decision Log

**2025-10-26:**
- ✅ Decided to use CGI instead of Rails route for better isolation
- ✅ Chose smart detection over always-execute-all approach
- ✅ Prioritized selective prerender for performance
- ✅ Selected 10-minute timeout as safe for longest operations

---

## References

- [Navigator CGI Documentation](https://rubys.github.io/navigator/features/cgi-scripts/)
- [CGI/1.1 Specification (RFC 3875)](https://www.rfc-editor.org/rfc/rfc3875.html)
- Blog post: "Bringing CGI Back from the Dead" (src/3379.md)
- Current implementation: `app/controllers/event_controller.rb#index_update`
- Initialization script: `script/nav_initialization.rb`
