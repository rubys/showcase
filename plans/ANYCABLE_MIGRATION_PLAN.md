# AnyCable Migration Plan

## Executive Summary: Memory Savings

This migration provides significant memory savings compared to Action Cable, making it the recommended approach over on-demand Action Cable startup.

### Memory Usage Comparison (per region)

| Configuration | navigator | WebSocket Server | Redis | **Total** | Savings |
|---------------|-----------|------------------|-------|-----------|---------|
| **Current: Action Cable (always-on)** | 17.6MB | 137.8MB (Puma/Rails) | 13.5MB | **169MB** | baseline |
| **Alternative: On-demand Action Cable (disabled)** | 17.6MB | 0MB | 13.5MB | **31MB** | 138MB (82%) |
| **Alternative: On-demand Action Cable (enabled, optimized)** | 17.6MB | 90-115MB (Puma/Rails) | 13.5MB | **121-146MB** | 23-48MB (14-28%) |
| **Part 2: AnyCable (separate binary, with Redis)** | 17.6MB | 20-30MB (Go) | 13.5MB | **51-61MB** | 108-118MB (64-70%) |
| **Part 2: AnyCable (separate binary, no Redis)** | 17.6MB | 20-30MB (Go) | 0MB | **38-48MB** | 121-131MB (72-77%) |
| **Part 3: Integrated Navigator + AnyCable (recommended)** | 25-35MB | (integrated) | 0MB | **25-35MB** | **134-144MB (79-85%)** |

### Key Insights

1. **Integrated Navigator + AnyCable (Part 3) is the best option** - Single 25-35MB binary saves 134-144MB per region (79-85% reduction)
2. **Part 3 beats separate AnyCable (Part 2)** - Additional 12.6-22.6MB saved per region through process consolidation
3. **WebSockets always available** - No manual enable/disable, no on-demand complexity, no startup delay
4. **Better than optimized Action Cable** - Even "optimized" Action Cable (121-146MB) uses 3-4× more memory than integrated solution (25-35MB)
5. **Scales across 8 regions**: 134-144MB × 8 = **1,072-1,152MB total savings** (over 1GB freed up!)

### Comparison with ACTION_CABLE_ON_DEMAND.md

| Metric | On-demand Action Cable | Part 2 (Separate AnyCable) | Part 3 (Integrated) |
|--------|----------------------|---------------------------|---------------------|
| **Memory saved (disabled/no Redis)** | 138MB | 121-131MB | **134-144MB** |
| **Memory saved (enabled/with Redis)** | 36-61MB | 108-118MB | **134-144MB** |
| **WebSockets always available?** | ❌ No (manual enable) | ✅ Yes | ✅ Yes |
| **Manual intervention needed?** | ✅ Yes (enable/disable) | ❌ No | ❌ No |
| **Startup delay?** | 2-3 seconds | None | None |
| **Number of binaries** | 1 (Rails) | 2 (Navigator + AnyCable) | **1 (Navigator)** |
| **Number of processes** | 1-2 (conditional) | 2 | **1** |
| **Performance** | Ruby/Puma | Go (better) | **Go (best)** |
| **Operational complexity** | Higher | Medium | **Lowest** |
| **Binary size total** | N/A | 55MB | **20-25MB** |

### Recommendation

**Implement Part 1 + Part 3 (skip Part 2)** because:
- ✅ **Best memory savings**: 134-144MB per region (over 1GB total across 8 regions)
- ✅ **Simplest deployment**: Single binary, one configuration, one process
- ✅ **WebSockets always available**: No manual intervention, no startup delay
- ✅ **Better performance**: Go-based, handles 100k+ concurrent connections
- ✅ **Smaller footprint**: 20-25MB total vs 55MB for separate binaries
- ✅ **Production-proven**: Leverages battle-tested AnyCable code
- ✅ **MIT licensed**: Legal to integrate with proper attribution

**Migration path**:
1. **Part 1** (3-5 hours): Migrate OutputChannel to HTTP POST + Job
2. **Part 3** (2-3 days): Integrate AnyCable into Navigator

**Total effort**: ~3 days vs 5-11 hours for Part 1 + Part 2

**Why skip Part 2?** Part 3 provides better results with only slightly more effort (2-3 days vs 5-6 hours), and eliminates the need for separate binary deployment.

---

## Overview

**Current State**: Action Cable server runs as standalone process, but OutputChannel requires RPC-like behavior via `perform` actions, preventing migration to AnyCable standalone mode.

**Goal**: Migrate OutputChannel from WebSocket `perform` actions to HTTP POST + Job pattern, then optionally migrate to AnyCable standalone mode for better performance and scalability.

**Benefits**:
- Eliminate last RPC-style interaction in Action Cable
- Enable AnyCable standalone mode (no RPC server needed)
- Follow established patterns (`ConfigUpdateJob`, `OfflinePlaylistJob`)
- Cleaner architecture (no file-based token registry)
- Production-ready WebSocket server with better performance
- **Significant memory savings: 121-131MB per region (968-1,048MB across 8 regions)**

---

## Part 1: Migrate OutputChannel to HTTP POST + Job

> **STATUS: ✅ COMPLETED (2025-11-01)**
>
> **Implementation time**: ~2 hours
> **Result**: OutputChannel successfully migrated to HTTP POST + Job pattern
> **Key insight**: No REGISTRY file needed - HTTP authentication provides security
> **Commands working**: scopy, hetzner, flyio, vscode, db_browser, apply

### Current Architecture

**OutputChannel** uses Action Cable `perform` for command execution:

1. Controller calls `OutputChannel.register(:command_type)` → returns unique token
2. Token stored in YAML file (`tmp/tokens.yaml`)
3. View passes token to client via `data-stream="<%= @stream %>"`
4. Client subscribes to OutputChannel with token as stream name
5. Client calls `perform("command", params)` (WebSocket message)
6. Server looks up command type from registry file
7. Server executes command via `PTY.spawn`
8. Output streams back via `transmit` in real-time

**Used in 2 locations**:

1. **Event selection page** (`app/views/event/select.html.erb`):
   - `scopy` - Database copy tool
   - `hetzner` - Deploy to Hetzner
   - `flyio` - Deploy to Fly.io
   - `vscode` - Open in VSCode
   - `db_browser` - Open DB Browser for SQLite

2. **Admin apply page** (`app/views/admin/apply.html.erb`):
   - `apply` - Apply configuration changes

**Implementation files**:
- Channel: `app/channels/output_channel.rb`
- Stimulus: `app/javascript/controllers/submit_controller.js`
- JavaScript: `app/javascript/channels/output_channel.js`
- Registry: `tmp/tokens.yaml` (temporary file)

### Proposed Architecture

**HTTP POST + Job pattern** (matching `ConfigUpdateJob`, `OfflinePlaylistJob`):

1. Client clicks button → HTTP POST to `/commands/:command_type`
2. Controller creates `CommandExecutionJob` with unique stream name
3. Job executes `PTY.spawn` and broadcasts output to stream
4. Client subscribes to broadcast stream and receives real-time output
5. Job completes, broadcasts completion marker (`\u0004`)

**Stream naming**: `command_output_#{database}_#{user_id}_#{job_id}`

### Implementation Steps

#### Step 1: Create CommandExecutionJob

**File**: `app/jobs/command_execution_job.rb`

```ruby
class CommandExecutionJob < ApplicationJob
  queue_as :default

  COMMANDS = {
    apply: ->(params) {
      [RbConfig.ruby, "bin/apply-changes.rb"]
    },
    scopy: ->(params) {
      ["scopy"]
    },
    hetzner: ->(params) {
      ["showcase", "-h"]
    },
    flyio: ->(params) {
      ["showcase", "-f"]
    },
    vscode: ->(params) {
      ["showcase", "-e"]
    },
    db_browser: ->(params) {
      db_path = Rails.root.join("db", ENV['RAILS_APP_DB'] + ".sqlite3").to_s
      ["open", "-a", "/Applications/DB Browser for SQLite.app", db_path]
    }
  }

  def perform(command_type, user_id, database, params = {})
    command_sym = command_type.to_sym
    block = COMMANDS[command_sym]

    unless block
      Rails.logger.error("Unknown command: #{command_type}")
      return
    end

    stream = "command_output_#{database}_#{user_id}_#{job_id}"
    command = block.call(params)

    Rails.logger.info("Executing command: #{command_sym} via #{stream}")

    execute_command(stream, command)
  end

  private

  BLOCK_SIZE = 4096

  def execute_command(stream, command)
    require 'pty'

    path = ENV['PATH']
    if Dir.exist? "/opt/homebrew/opt/ruby/bin"
      path = "/opt/homebrew/opt/ruby/bin:#{path}"
    end

    PTY.spawn({"PATH" => path}, *command) do |read, write, pid|
      write.close

      while !read.eof
        output = read.readpartial(BLOCK_SIZE)
        ActionCable.server.broadcast(stream, output)
      end

    rescue EOFError
    rescue Interrupt
    rescue => e
      Rails.logger.error("CommandExecutionJob error: #{e}")
      ActionCable.server.broadcast(stream, "\nError: #{e.message}\n")
    ensure
      read.close
    end

    # Send completion marker
    ActionCable.server.broadcast(stream, "\u0004")
  end
end
```

#### Step 2: Add controller action

**File**: `app/controllers/event_controller.rb`

Add new action:

```ruby
def execute_command
  user = User.find_by(userid: @authuser)
  unless user
    render json: { error: 'User not found' }, status: :unauthorized
    return
  end

  command_type = params[:command_type]
  unless CommandExecutionJob::COMMANDS.key?(command_type.to_sym)
    render json: { error: 'Invalid command' }, status: :bad_request
    return
  end

  database = ENV['RAILS_APP_DB']

  # Start job and get job_id for stream name
  job = CommandExecutionJob.perform_later(
    command_type,
    user.id,
    database,
    params[:params] || {}
  )

  stream = "command_output_#{database}_#{user.id}_#{job.job_id}"

  render json: { stream: stream }
end
```

**File**: `config/routes.rb`

Add route:

```ruby
post 'commands/:command_type', to: 'event#execute_command', as: :execute_command
```

#### Step 3: Create CommandOutputChannel

**File**: `app/channels/command_output_channel.rb`

```ruby
class CommandOutputChannel < ApplicationCable::Channel
  def subscribed
    database = params[:database]
    user_id = params[:user_id]
    job_id = params[:job_id]

    # Verify user authorization
    # (Add authorization logic as needed)

    stream_from "command_output_#{database}_#{user_id}_#{job_id}"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
```

#### Step 4: Update Stimulus controller

**File**: `app/javascript/controllers/submit_controller.js`

Replace WebSocket `perform` with HTTP POST:

```javascript
import { Controller } from "@hotwired/stimulus"
import consumer from 'channels/consumer'
import xterm from '@xterm/xterm';

export default class extends Controller {
  static targets = ["input", "submit", "output"]

  connect() {
    this.activeSubscription = null
    this.terminal = null

    this.cleanup()

    this.handlePageUnload = () => {
      this.cleanup()
    }
    window.addEventListener('beforeunload', this.handlePageUnload)
    window.addEventListener('pagehide', this.handlePageUnload)

    this.submitTargets.forEach(submitTarget => {
      submitTarget.addEventListener('click', async (event) => {
        event.preventDefault()

        this.cleanup()

        const { outputTarget } = this
        const commandType = submitTarget.dataset.commandType

        if (!commandType) {
          console.error('No command type found for button:', submitTarget.textContent)
          return
        }

        submitTarget.disabled = true

        // Collect parameters
        const params = {}
        for (const input of this.inputTargets) {
          params[input.name] = input.value
        }

        try {
          // POST to start job
          const response = await fetch(`/commands/${commandType}`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
            },
            body: JSON.stringify({ params })
          })

          if (!response.ok) {
            throw new Error(`HTTP ${response.status}`)
          }

          const { stream } = await response.json()

          // Parse stream name to get components
          const match = stream.match(/command_output_(.+)_(\d+)_(.+)/)
          if (!match) {
            throw new Error('Invalid stream format')
          }

          const [, database, userId, jobId] = match

          // Subscribe to output stream
          this.activeSubscription = consumer.subscriptions.create({
            channel: "CommandOutputChannel",
            database: database,
            user_id: userId,
            job_id: jobId
          }, {
            connected() {
              outputTarget.parentNode.classList.remove("hidden")
              outputTarget.innerHTML = ''
              this.controller.terminal = new xterm.Terminal()
              this.controller.terminal.open(outputTarget)
            },

            received(data) {
              if (data === "\u0004") {
                // Completion marker
                this.disconnected()
              } else {
                this.controller.terminal?.write(data)
              }
            },

            disconnected() {
              submitTarget.disabled = false
            }
          })

          this.activeSubscription.controller = this

        } catch (error) {
          console.error('Failed to start command:', error)
          submitTarget.disabled = false
          alert(`Failed to start command: ${error.message}`)
        }
      })
    })
  }

  cleanup() {
    if (this.activeSubscription) {
      this.activeSubscription.unsubscribe()
      this.activeSubscription = null
    }

    if (consumer && consumer.subscriptions) {
      const commandSubscriptions = consumer.subscriptions.subscriptions.filter(
        subscription => subscription.identifier &&
          JSON.parse(subscription.identifier).channel === 'CommandOutputChannel'
      )
      commandSubscriptions.forEach(subscription => {
        subscription.unsubscribe()
      })
    }

    if (this.terminal) {
      this.terminal.dispose()
      this.terminal = null
    }

    if (this.hasOutputTarget) {
      this.outputTarget.innerHTML = ''
    }
  }

  disconnect() {
    this.cleanup()

    if (this.handlePageUnload) {
      window.removeEventListener('beforeunload', this.handlePageUnload)
      window.removeEventListener('pagehide', this.handlePageUnload)
    }
  }
}
```

#### Step 5: Update views

**File**: `app/views/event/select.html.erb`

Change from:

```erb
<button data-submit-target="submit" data-stream="<%= @scopy_stream %>" type="button"
  class="btn-purple">Scopy</button>
```

To:

```erb
<button data-submit-target="submit" data-command-type="scopy" type="button"
  class="btn-purple">Scopy</button>
```

Apply same pattern for all other buttons:
- `data-stream="<%= @hetzner_stream %>"` → `data-command-type="hetzner"`
- `data-stream="<%= @flyio_stream %>"` → `data-command-type="flyio"`
- `data-stream="<%= @vscode_stream %>"` → `data-command-type="vscode"`
- `data-stream="<%= @db_browser_stream %>"` → `data-command-type="db_browser"`

**File**: `app/views/admin/apply.html.erb`

Change from:

```erb
<button data-submit-target="submit" data-stream="<%= @stream %>" type="button"
  class="btn-blue">Apply Changes</button>
```

To:

```erb
<button data-submit-target="submit" data-command-type="apply" type="button"
  class="btn-blue">Apply Changes</button>
```

#### Step 6: Remove OutputChannel registration from controllers

**File**: `app/controllers/event_controller.rb`

Remove from `select` action:

```ruby
# DELETE these lines:
@scopy_stream = OutputChannel.register(:scopy)
@hetzner_stream = OutputChannel.register(:hetzner)
@flyio_stream = OutputChannel.register(:flyio)
@vscode_stream = OutputChannel.register(:vscode)
@db_browser_stream = OutputChannel.register(:db_browser)
```

**File**: `app/controllers/admin_controller.rb`

Remove from `apply` action:

```ruby
# DELETE this line:
@stream = OutputChannel.register(:apply)
```

#### Step 7: Remove old OutputChannel files

Once migration is complete and tested:

1. Delete `app/channels/output_channel.rb`
2. Delete `app/javascript/channels/output_channel.js` (if unused)
3. Delete `test/channels/output_channel_test.rb`
4. Remove token registry cleanup (no longer needed)

### Testing Plan

Test each command type:

1. **scopy** - Database copy tool
   - Verify real-time output appears
   - Verify completion marker works
   - Check terminal display

2. **hetzner** - Deploy to Hetzner
   - Test deployment command execution
   - Verify output streaming

3. **flyio** - Deploy to Fly.io
   - Test deployment command execution
   - Verify output streaming

4. **vscode** - Open in VSCode
   - Verify VSCode opens (local development)

5. **db_browser** - Open DB Browser
   - Verify application launches (local development)

6. **apply** - Configuration changes
   - Test on admin page
   - Verify change application works

### Rollback Plan

If issues arise:
1. Revert controller changes
2. Re-add `OutputChannel.register` calls
3. Revert view changes (use `data-stream` again)
4. Keep old `OutputChannel` class temporarily

---

## Part 2: Optional - Migrate to AnyCable Standalone Mode

> **UPDATE (2025-11-01)**: After analysis, **integrating AnyCable into Navigator** as a single binary is recommended over running AnyCable as a separate process. See [Part 3: Alternative - Integrated Navigator + AnyCable](#part-3-alternative---integrated-navigator--anycable) for details.

**Prerequisites**: Part 1 must be complete and tested.

**Note**: This approach uses AnyCable as a separate binary. For even better memory savings and simpler deployment, see Part 3 below.

### Current Action Cable Usage (After Part 1)

All channels will be broadcast-only (no `perform` actions):

1. **CurrentHeatChannel** - streams `current-heat-#{database}`
2. **ScoresChannel** - streams `live-scores-#{database}`
3. **ConfigUpdateChannel** - streams `config_update_{database}_{user_id}`
4. **OfflinePlaylistChannel** - streams `offline_playlist_{database}_{user_id}`
5. **CommandOutputChannel** - streams `command_output_{database}_{user_id}_{job_id}`

All use simple `stream_from` with tenant-specific stream names.

### Benefits of AnyCable

- **Performance**: Written in Go, handles 100k+ concurrent connections
- **Lower memory**: ~20-30MB vs ~138MB for Action Cable
- **Production-proven**: Used by major Rails applications
- **Drop-in replacement**: Compatible with Action Cable protocol
- **Standalone mode**: No RPC server needed for broadcast-only usage

### Architecture Changes

**Current**:
```
Client → Navigator → Rails Action Cable Server (Puma) → Redis → Tenants
```

**With AnyCable**:
```
Client → Navigator → AnyCable-Go Server → HTTP Broadcaster ← Rails Apps
```

### Implementation Steps

#### Step 1: Add AnyCable to Docker image

**File**: `Dockerfile`

```dockerfile
# Add AnyCable installation
RUN curl -sL https://github.com/anycable/anycable-go/releases/download/v1.5.1/anycable-go-linux-amd64 \
  -o /usr/local/bin/anycable-go && \
  chmod +x /usr/local/bin/anycable-go
```

#### Step 2: Update Navigator configuration

**File**: `app/controllers/concerns/configurator.rb`

Replace Action Cable process configuration with AnyCable:

```ruby
# OLD:
processes << {
  'name' => 'action-cable',
  'command' => 'bundle',
  'args' => ['exec', 'puma', '-p', ENV.fetch('CABLE_PORT', '28080'), 'cable/config.ru'],
  'auto_restart' => true,
  'start_delay' => '1s'
}

# NEW:
processes << {
  'name' => 'anycable',
  'command' => 'anycable-go',
  'args' => [
    '--port', ENV.fetch('CABLE_PORT', '28080'),
    '--broadcast_adapter', 'http',
    '--http_broadcast_port', ENV.fetch('BROADCAST_PORT', '28081'),
    '--norpc',  # No RPC server needed
    '--noauth', # Authentication handled by Navigator
    '--public_streams' # Allow public stream subscriptions
  ],
  'auto_restart' => true,
  'start_delay' => '1s'
}
```

#### Step 3: Update Rails broadcasting (HTTP Broadcaster - Recommended)

**Benefits of HTTP broadcaster**:
- ✅ **Eliminates Redis dependency** - saves 13.5MB per region (108MB across 8 regions)
- ✅ Simpler architecture (one less service to manage)
- ✅ Better for multi-region (no Redis replication needed)
- ✅ Direct HTTP calls (no message queue latency)
- ✅ No additional gems required

**How it works**:
1. Rails calls `ActionCable.server.broadcast(stream, data)`
2. ActionCable makes HTTP POST to AnyCable's `/_broadcast` endpoint
3. AnyCable receives broadcast and sends to all subscribed WebSocket clients
4. **No Redis involved** - direct Rails → AnyCable → Clients

**IMPORTANT**: Cannot use `:async` adapter because Rails app and Action Cable server run as **separate processes**. The `:async` adapter only broadcasts within a single process (in-memory), so broadcasts from Rails would never reach the Action Cable server where WebSocket connections live.

**Solution**: Use `anycable-rails` gem with HTTP broadcaster:

**File**: `Gemfile`

```ruby
gem 'anycable-rails', '~> 1.5'
```

Then run: `bundle install`

**File**: `config/cable.yml`

```ruby
production:
  adapter: any_cable  # Use AnyCable adapter (NOT async, NOT redis)
```

**File**: `config/anycable.yml` (create this file)

```yaml
production:
  # Use HTTP to broadcast from Rails to Navigator's WebSocket server
  broadcast_adapter: http

  # Navigator's integrated WebSocket server broadcast endpoint
  http_broadcast_url: "http://localhost:#{ENV.fetch('CABLE_PORT', '28080')}/_broadcast"

  # Optional: secure broadcasts with a key
  # broadcast_key: <%= ENV['ANYCABLE_BROADCAST_KEY'] %>
```

**Broadcasting implementation**: Existing broadcasts work without changes:

```ruby
# Existing code - no changes needed!
ActionCable.server.broadcast(
  "command_output_#{database}_#{user_id}_#{job_id}",
  output
)
```

**How it works**:
1. Rails calls `ActionCable.server.broadcast(stream, data)`
2. anycable-rails gem intercepts this (via `:any_cable` adapter)
3. HTTP POST sent to Navigator's `/_broadcast` endpoint
4. Navigator's integrated AnyCable broadcasts to all WebSocket clients
5. **No Redis needed** - broadcasts go directly via HTTP

#### Step 3b: Remove Redis from managed processes

Since Redis is no longer needed for Action Cable (HTTP broadcaster handles pub/sub), remove it from Navigator's managed processes.

**File**: `app/controllers/concerns/configurator.rb`

Find the `build_managed_processes_config` method and remove the Redis process:

```ruby
def build_managed_processes_config
  processes = []

  # AnyCable WebSocket server
  processes << {
    'name' => 'anycable',
    'command' => 'anycable-go',
    'args' => [
      '--port', ENV.fetch('CABLE_PORT', '28080'),
      '--broadcast_adapter', 'http',
      '--http_broadcast_port', ENV.fetch('BROADCAST_PORT', '28081'),
      '--norpc',
      '--noauth',
      '--public_streams'
    ],
    'auto_restart' => true,
    'start_delay' => '1s'
  }

  # Redis no longer needed - HTTP broadcaster handles pub/sub
  # REMOVE this entire block:
  # if ENV['FLY_APP_NAME']
  #   processes << {
  #     'name' => 'redis',
  #     'command' => 'redis-server',
  #     'args' => ['/etc/redis/redis.conf'],
  #     'working_dir' => Rails.root.to_s,
  #     'env' => {},
  #     'auto_restart' => true,
  #     'start_delay' => '2s'
  #   }
  # end

  processes
end
```

**Memory impact**:
- Removes 13.5MB Redis process
- Total AnyCable footprint: 20-30MB (vs 169MB baseline)
- **Total savings: 121-131MB per region**

**Important**: Verify that Redis is not used elsewhere in the application:
```bash
# Search for Redis usage
grep -r "Redis\|REDIS" app/ config/ --include="*.rb"
```

If Redis is used for other purposes (caching, Sidekiq, etc.), you'll need to keep it. However, for pure Action Cable broadcasting, it's not needed with AnyCable's HTTP broadcaster.

#### Step 4: Update client subscriptions (signed streams)

**File**: `app/helpers/application_helper.rb`

Add helper for signed stream names:

```ruby
def signed_stream_name(stream)
  # Generate signed stream name using Rails secret
  AnyCable::Streams.signed(stream)
end
```

**Update channels to use signed streams**:

Channels remain the same (they still use `stream_from`), but clients subscribe differently.

**Client-side changes**: Minimal or none if using AnyCable's Action Cable compatibility mode.

#### Step 5: Testing

1. **Start AnyCable locally**:
   ```bash
   anycable-go --port 28080 --broadcast_adapter http --norpc --public_streams
   ```

2. **Test each channel**:
   - CurrentHeatChannel - update heat number
   - ScoresChannel - enter scores
   - ConfigUpdateChannel - trigger config update
   - OfflinePlaylistChannel - generate playlist
   - CommandOutputChannel - run commands

3. **Monitor performance**:
   ```bash
   # Check memory usage
   ps aux | grep anycable-go

   # Check connections
   curl http://localhost:28080/health
   ```

#### Step 6: Deployment

Deploy with AnyCable configuration:

```bash
fly deploy
```

Monitor for issues:
- WebSocket connection success rate
- Broadcast delivery
- Memory usage
- Error logs

### Rollback Plan

If AnyCable causes issues:

1. Revert Dockerfile changes
2. Revert Navigator configuration (back to Puma Action Cable)
3. Revert Rails configuration
4. Redeploy

### Performance Comparison

**Before (Action Cable with Puma)**:
- Memory: ~138MB per instance
- Connections: ~1000 per process
- CPU: Ruby process overhead

**After (AnyCable)**:
- Memory: ~20-30MB per instance
- Connections: 100k+ capable
- CPU: Minimal (Go efficiency)

**Estimated savings**: ~110MB per machine × 8 machines = ~880MB total

---

## Success Criteria

### Part 1 Complete When:
- [ ] All 6 command types work via HTTP POST
- [ ] Real-time output streams correctly
- [ ] Terminal display works (xterm.js)
- [ ] No `OutputChannel` references remain
- [ ] No `tmp/tokens.yaml` file usage
- [ ] Tests pass

### Part 2 Complete When:
- [ ] AnyCable runs in production
- [ ] All 5 channels work correctly
- [ ] Broadcasting works reliably
- [ ] Memory usage reduced
- [ ] No WebSocket errors in logs
- [ ] Performance improved

---

## Part 3: Alternative - Integrated Navigator + AnyCable

> **RECOMMENDED APPROACH**: This provides better memory savings and simpler deployment than Part 2.

### Overview

Instead of running AnyCable as a separate binary, integrate its WebSocket functionality directly into Navigator. Both are MIT-licensed Go projects, making this legally and technically feasible.

### Benefits vs Separate AnyCable Binary (Part 2)

| Metric | Part 2 (Separate) | Part 3 (Integrated) | Improvement |
|--------|------------------|---------------------|-------------|
| **Processes** | 2 (Navigator + AnyCable) | 1 (Navigator only) | Simpler |
| **Memory (runtime)** | 37.6-47.6MB | 25-35MB | 12.6-22.6MB saved |
| **Total savings (8 regions)** | 864-944MB | 968-1,048MB + 100-180MB = **1,068-1,228MB** | +204-284MB |
| **Binary size** | 10MB + 45MB = 55MB total | 20-25MB | 30-35MB smaller |
| **Configuration files** | 2 (Navigator + AnyCable) | 1 (Navigator only) | Simpler |
| **Port coordination** | Needed (28080, 28081) | Not needed | Simpler |
| **Process management** | Manage 2 processes | Manage 1 process | Simpler |
| **Deployment** | 2 binaries to build/deploy | 1 binary to build/deploy | Simpler |

### Why This Works

**Both projects are Go + MIT licensed**:
- **Navigator**: ~25k LOC, 10MB binary, MIT (Ruby Sam)
- **AnyCable-Go**: ~37k LOC, 45MB binary, MIT (Vladimir Dementyev)

**Shared architecture patterns**:
- HTTP server setup
- YAML configuration
- Process management
- Structured logging (slog)
- Graceful shutdown
- Signal handling

**Legal compatibility**: Both MIT licenses allow integration with proper attribution.

### Technical Architecture

**Current (Part 2 approach)**:
```
┌─────────────────────────────────────────────┐
│ Machine                                     │
│                                             │
│  ┌──────────────┐       ┌──────────────┐  │
│  │ Navigator    │──────>│ AnyCable-Go  │  │
│  │ 17.6MB       │       │ 20-30MB      │  │
│  │              │       │              │  │
│  │ - HTTP       │       │ - WebSocket  │  │
│  │ - Proxy      │       │ - Broadcast  │  │
│  │ - Auth       │       │              │  │
│  └──────────────┘       └──────────────┘  │
│                                             │
│  Total: 37.6-47.6MB                        │
└─────────────────────────────────────────────┘
```

**Integrated (Part 3 approach)**:
```
┌─────────────────────────────────────────────┐
│ Machine                                     │
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │ Navigator (with integrated WebSocket)│  │
│  │ 25-35MB                              │  │
│  │                                      │  │
│  │ - HTTP                               │  │
│  │ - Proxy                              │  │
│  │ - Auth                               │  │
│  │ - WebSocket (from AnyCable)         │  │
│  │ - Broadcast                          │  │
│  └──────────────────────────────────────┘  │
│                                             │
│  Total: 25-35MB                            │
└─────────────────────────────────────────────┘
```

### Implementation Approaches

#### **Option A: Module Import (Recommended for Phase 1)**

Import AnyCable-Go as a Go module dependency:

**Estimated effort**: 1-2 days

**File**: `navigator/go.mod`
```go
require (
    github.com/anycable/anycable-go v1.5.1
)
```

**File**: `navigator/internal/websocket/handler.go`
```go
package websocket

import (
    "github.com/anycable/anycable-go/server"
    "github.com/anycable/anycable-go/ws"
)

type Handler struct {
    server *server.Server
}

func NewHandler(config *Config) (*Handler, error) {
    // Initialize AnyCable server in standalone mode
    srv := server.New(&server.Config{
        Port:              config.Port,
        BroadcastAdapter:  "http",
        HTTPBroadcastPort: config.BroadcastPort,
        NoRPC:             true,
        NoAuth:            true, // Navigator handles auth
        PublicStreams:     true,
    })

    return &Handler{server: srv}, nil
}

func (h *Handler) HandleWebSocket(w http.ResponseWriter, r *http.Request) {
    h.server.HandleWebSocket(w, r)
}
```

**File**: `navigator/internal/server/router.go`
```go
func (s *Server) setupRoutes() {
    // ... existing routes ...

    // WebSocket endpoint
    if s.config.WebSocket.Enabled {
        s.mux.HandleFunc("/cable", s.websocketHandler.HandleWebSocket)
        s.mux.HandleFunc("/_broadcast", s.websocketHandler.HandleBroadcast)
    }
}
```

**Pros**:
- ✅ Quick implementation (1-2 days)
- ✅ Battle-tested AnyCable code
- ✅ Easy to maintain (upstream updates via go get)
- ✅ Full AnyCable feature set available

**Cons**:
- ⚠️ Larger binary (includes unused features like NATS, Redis adapters)
- ⚠️ Dependency on external module

#### **Option B: Code Integration (Recommended for Phase 2)**

Extract only needed AnyCable packages into Navigator:

**Estimated effort**: 2-3 days

**File structure**:
```
navigator/
  internal/
    websocket/
      protocol.go      ← Action Cable protocol
      handler.go       ← WebSocket upgrade & handling
      streams.go       ← Stream management
    broadcast/
      http.go          ← HTTP broadcaster endpoint
    actioncable/
      messages.go      ← Message types (welcome, ping, etc.)
      subscriptions.go ← Subscription management
```

**What to extract from AnyCable**:
- `ws/` - WebSocket handler (gorilla/websocket)
- `node/` - Connection management
- `broadcast/http` - HTTP broadcaster
- `protocol/` - Action Cable protocol
- `streams/` - Stream management

**What to exclude**:
- RPC server code
- NATS adapter
- Redis adapter
- Metrics (use Navigator's approach)
- CLI (use Navigator's CLI)

**Pros**:
- ✅ Smaller binary (~15-18MB vs 20-25MB)
- ✅ Tighter integration with Navigator
- ✅ No external dependencies
- ✅ Full control over code

**Cons**:
- ⚠️ More implementation effort
- ⚠️ Need to track AnyCable updates manually
- ⚠️ More testing required

#### **Option C: Minimal Implementation (Not Recommended)**

Build minimal WebSocket support from scratch:

**Estimated effort**: 3-4 days

**What to build**:
- WebSocket upgrade
- Action Cable protocol subset (subscribe, unsubscribe, message)
- Stream broadcasting
- HTTP broadcaster endpoint

**Pros**:
- ✅ Smallest binary (~12-15MB)
- ✅ Tailored exactly to Showcase needs

**Cons**:
- ❌ More development time
- ❌ Less battle-tested
- ❌ More maintenance burden
- ❌ Missing features if needed later

### Recommended Implementation Plan

**Phase 1: Quick Win (Option A - Module Import)**

1. Add AnyCable-Go to Navigator's go.mod
2. Create `internal/websocket` package wrapping AnyCable
3. Add WebSocket routes to Navigator's HTTP handler
4. Add `websocket` section to navigator.yml
5. Test with Showcase channels
6. Deploy to staging

**Timeline**: 1-2 days implementation + 1 day testing

**Phase 2: Optimization (Option B - Code Integration)** *(optional, future)*

1. Extract needed AnyCable packages
2. Remove unused features
3. Integrate more tightly with Navigator
4. Optimize for size and performance

**Timeline**: 2-3 days implementation + 1 day testing

### Configuration Changes Summary

**What needs to change**:

1. **Add gem**: `anycable-rails` to Gemfile
2. **Change adapter**: `config/cable.yml` → `adapter: any_cable` (not `async`, not `redis`)
3. **Create config**: `config/anycable.yml` with HTTP broadcast settings
4. **Add Navigator config**: `config/navigator.yml` → `server.websocket` section
5. **Remove processes**: Delete Action Cable and Redis from `configurator.rb`

**What stays the same**:
- ✅ All channel files unchanged
- ✅ All `ActionCable.server.broadcast` calls unchanged
- ✅ Client JavaScript unchanged (still connects to `/cable`)
- ✅ Stream naming unchanged

### Configuration Details

**File**: `config/navigator.yml`

```yaml
server:
  listen: 3000
  hostname: localhost

  # WebSocket configuration
  websocket:
    enabled: true
    broadcast_adapter: http
    broadcast_port: 28081
    public_streams: true  # No auth for streams (Navigator handles at connection level)

applications:
  tenants:
    - name: "2025-boston"
      root: /path/to/app
      # ... tenant config ...
```

### Rails Configuration

**IMPORTANT**: Cannot use `:async` adapter because Rails app and Action Cable server run as **separate processes**. The `:async` adapter only broadcasts within a single process (in-memory).

**Solution**: Use `anycable-rails` gem with HTTP broadcaster (same as Part 2):

**File**: `Gemfile`

```ruby
gem 'anycable-rails', '~> 1.5'
```

**File**: `config/cable.yml`

```yaml
production:
  adapter: any_cable  # Use AnyCable adapter (NOT async, NOT redis)
```

**File**: `config/anycable.yml`

```yaml
production:
  broadcast_adapter: http
  http_broadcast_url: "http://localhost:3000/_broadcast"  # Navigator's integrated endpoint
```

**No changes needed** to existing `ActionCable.server.broadcast` calls!

### Memory Savings Breakdown

**Current baseline (Action Cable + Puma)**:
```
navigator:     17.6MB
action-cable: 137.8MB
redis:         13.5MB
Total:        169MB
```

**Part 2 (Separate AnyCable binary)**:
```
navigator:     17.6MB
anycable-go:   20-30MB
Total:         37.6-47.6MB
Savings:       121.4-131.4MB (72-77%)
```

**Part 3 (Integrated Navigator + AnyCable)**:
```
navigator:     25-35MB  (includes WebSocket)
Total:         25-35MB
Savings:       134-144MB (79-85%)
```

**Additional savings from single process**:
- Shared HTTP server
- Shared runtime
- Deduplicated dependencies
- **Extra 12.6-22.6MB per region**
- **Extra 100-180MB across 8 regions**

### Testing Plan

**Unit tests**:
```bash
# Test WebSocket upgrade
go test ./internal/websocket/...

# Test Action Cable protocol
go test ./internal/actioncable/...

# Test HTTP broadcaster
go test ./internal/broadcast/...
```

**Integration tests**:
```bash
# Start Navigator with WebSocket enabled
./bin/navigator --config config/navigator.yml

# Test WebSocket connection
wscat -c ws://localhost:3000/cable

# Test broadcast endpoint
curl -X POST http://localhost:3000/_broadcast \
  -H "Content-Type: application/json" \
  -d '{"stream":"test","data":"hello"}'
```

**Showcase integration**:
1. Update Showcase channels to connect to Navigator's `/cable`
2. Test each channel:
   - CurrentHeatChannel
   - ScoresChannel
   - ConfigUpdateChannel
   - OfflinePlaylistChannel
   - CommandOutputChannel
3. Verify real-time updates work
4. Monitor memory usage

### Rollback Plan

If integration causes issues:

1. **Quick rollback**: Disable WebSocket in configuration
   ```yaml
   websocket:
     enabled: false
   ```

2. **Full rollback**: Deploy previous Navigator version
   ```bash
   git revert <commit-hash>
   cd navigator && make build && fly deploy
   ```

3. **Fallback to Part 2**: Deploy AnyCable as separate binary
   - Keep integrated code
   - Run AnyCable separately
   - Point Rails to separate AnyCable

### Success Criteria

- ✅ Single Navigator binary includes WebSocket functionality
- ✅ All 5 Showcase channels work correctly
- ✅ Real-time updates function as expected
- ✅ Memory usage: 25-35MB (vs 37.6-47.6MB separate)
- ✅ Binary size: 20-25MB (vs 10MB + 45MB = 55MB separate)
- ✅ No WebSocket connection errors
- ✅ HTTP broadcasting works reliably
- ✅ Graceful shutdown handles active WebSocket connections

### Deployment Strategy

**Week 1**: Implement Option A (Module Import)
- Add AnyCable as dependency
- Create WebSocket wrapper package
- Update Navigator configuration
- Local testing

**Week 2**: Test with Showcase
- Deploy to local dev
- Test all channels
- Measure memory usage
- Fix any issues

**Week 3**: Staging deployment
- Deploy to staging region
- Monitor for 1 week
- Collect metrics
- User acceptance testing

**Week 4**: Production rollout
- Deploy to 1 region
- Monitor for issues
- Gradual rollout to all 8 regions
- Monitor memory savings

**Week 5+**: Optional optimization (Option B)
- Extract AnyCable code
- Reduce binary size
- Further optimize

### License Attribution

**File**: `navigator/internal/websocket/LICENSE.anycable`

```
This package incorporates code from AnyCable-Go:
https://github.com/anycable/anycable-go

Copyright 2016-2023 Vladimir Dementyev

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

[... full MIT license text ...]
```

**File**: `navigator/README.md` (update)

```markdown
## Credits

Navigator includes WebSocket functionality based on:
- [AnyCable-Go](https://github.com/anycable/anycable-go) by Vladimir Dementyev (MIT License)
```

---

## Timeline Estimate

**Part 1 (OutputChannel Migration)**:
- Implementation: 2-3 hours
- Testing: 1-2 hours
- Total: 3-5 hours

**Part 2 (AnyCable as Separate Binary)**:
- Setup: 1 hour
- Configuration: 2 hours
- Testing: 2-3 hours
- Monitoring: 1 week
- Total: 5-6 hours + monitoring

**Part 3 (Integrated Navigator + AnyCable)** - **RECOMMENDED**:
- Phase 1 (Module Import): 1-2 days implementation + 1 day testing
- Phase 2 (Code Integration): 2-3 days implementation + 1 day testing (optional)
- Total: 2-3 days (Phase 1 only) or 5-7 days (both phases)

---

## Related Documents

- `ACTION_CABLE_ON_DEMAND.md` - On-demand Action Cable startup (superseded by this plan)
- `ARCHITECTURE.md` - System architecture documentation
- AnyCable docs: https://docs.anycable.io
- AnyCable standalone mode: https://docs.anycable.io/anycable-go/getting_started#standalone-mode-pubsub-only
- Navigator repository: https://github.com/rubys/navigator

---

## Recommendations Summary

### Recommended Approach: Part 1 → Part 3

1. **Part 1: OutputChannel Migration** (3-5 hours)
   - Migrate to HTTP POST + Job pattern
   - Prerequisite for both Part 2 and Part 3
   - Valuable on its own (cleaner architecture)

2. **Part 3: Integrated Navigator + AnyCable** (2-3 days)
   - **Better than Part 2**: Additional 100-180MB memory savings
   - **Simpler**: Single binary, one configuration, one process
   - **Battle-tested**: Leverages proven AnyCable code
   - **Future-proof**: Can optimize further with Phase 2

### Why Not Part 2?

Part 2 (separate AnyCable binary) is still viable but **Part 3 is superior**:
- Part 2 saves 121-131MB per region
- Part 3 saves 134-144MB per region (extra 12.6-22.6MB)
- Part 3 is operationally simpler (one binary vs two)
- Part 3 has smaller deployment footprint (20-25MB vs 55MB total)

**Use Part 2 only if**:
- Cannot modify Navigator (organizational constraints)
- Want to test AnyCable separately first
- Need quick deployment without Navigator changes

### Total Memory Savings (All 8 Regions)

| Approach | Per Region | Total (8 regions) |
|----------|-----------|-------------------|
| Part 2 (Separate AnyCable) | 121-131MB | 968-1,048MB |
| **Part 3 (Integrated)** | **134-144MB** | **1,068-1,152MB** |
| **Difference** | **+13MB** | **+100-180MB extra** |

---

## Notes

- **Part 1 is required** for both Part 2 and Part 3
- **Part 3 is recommended** over Part 2 for production deployment
- Part 2 can be used as a stepping stone to Part 3
- All approaches eliminate Redis when using HTTP broadcaster
- AnyCable integration is MIT-licensed and legally compatible
- Can test Part 3 locally before production deployment
- Rollback options available at every stage
