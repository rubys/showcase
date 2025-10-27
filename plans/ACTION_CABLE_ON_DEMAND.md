# Action Cable On-Demand Startup Plan

## Overview

**Current State**: Action Cable server (Puma on port 28080) starts automatically on every cold start, consuming ~138MB (6.8% of 2GB) even when not in use.

**Goal**: Start Action Cable only when WebSocket connections are actually needed, saving ~138MB during typical page browsing.

**Architecture**: All tenant WebSocket requests are routed to a single Action Cable server via reverse proxy:
- URL Pattern: `/showcase/regions/{region}/cable` or `/showcase/cable`
- Target: `http://localhost:28080/cable`
- Configuration: `app/controllers/concerns/configurator.rb` lines 238-261

**Current Memory Usage** (smooth-nav):
```
navigator:     17.6MB (0.8%)
action-cable: 137.8MB (6.8%)  ← Target for optimization
redis:         13.5MB (0.6%)
Total:        169MB (8.2%)
```

---

## Problem Analysis

### Why Action Cable Always Starts

Action Cable is configured as a managed process in Navigator:
- Location: `app/controllers/concerns/configurator.rb` lines 614-626
- Type: Managed process with `auto_restart: true`
- Start delay: 1 second after Navigator starts

```ruby
processes << {
  'name' => 'action-cable',
  'command' => 'bundle',
  'args' => ['exec', 'puma', '-p', ENV.fetch('CABLE_PORT', '28080'), 'cable/config.ru'],
  'auto_restart' => true,
  'start_delay' => '1s'
}
```

### When Action Cable Is Actually Used

Action Cable provides real-time WebSocket features for:

1. **Live Score Updates** - `app/javascript/channels/scores_channel.js`
   - Updates scores in real-time during judging
   - Used during active showcases by judges and staff

2. **Current Heat Updates** - `app/javascript/channels/current_heat_channel.js`
   - Updates current heat information on displays
   - Used during active showcases by attendees

3. **Console Output** - `app/javascript/channels/output_channel.js`
   - Streams command output to web interface
   - Used by administrators during system operations

**Usage Pattern**: These features are only needed during **active showcases** or **administrative operations**, not during normal page browsing.

### Memory Savings Opportunity

**Typical Usage Pattern**:
- Cold start → User browses studios/regions/events → No WebSockets needed
- **Savings**: 138MB (6.8% of total memory)

**Active Showcase Pattern**:
- User navigates to event → Opens scoring interface → Connects WebSocket
- **Cost**: Start Action Cable on-demand (~2-3s delay)

**Trade-off Analysis**:
- **Benefit**: Save 138MB (82% of baseline memory) during typical browsing
- **Cost**: 2-3 second delay when first WebSocket connection is made
- **User Impact**: Minimal - WebSocket features only needed during active events

---

## Implementation Approaches

### Approach 1: Simple - Make Action Cable Optional (Low Risk, Immediate)

**Concept**: Add environment variable to control whether Action Cable starts.

**Implementation**:

1. Add configuration flag in `configurator.rb`:
```ruby
def build_managed_processes_config
  processes = []

  # Only start Action Cable if explicitly enabled
  if ENV['ENABLE_ACTION_CABLE'] == 'true'
    processes << {
      'name' => 'action-cable',
      # ... existing config ...
    }
  end

  # Redis still starts (needed for other features)
  if ENV['FLY_APP_NAME']
    processes << {
      'name' => 'redis',
      # ... existing config ...
    }
  end

  processes
end
```

2. Enable for specific deployments via `fly.toml`:
```toml
[env]
  ENABLE_ACTION_CABLE = "false"  # Default: disabled

# Override for specific regions during events
[[override.regions.iad]]
  [override.regions.iad.env]
    ENABLE_ACTION_CABLE = "true"
```

3. Add manual start script for administrators:
```bash
# script/start_action_cable.sh
#!/bin/bash
fly ssh console -a smooth-nav -r "$FLY_REGION" -C "cd /rails && bundle exec puma -p 28080 -d cable/config.ru"
```

**Pros**:
- ✅ Simple to implement (5 lines of code)
- ✅ No Navigator changes needed
- ✅ Immediate memory savings
- ✅ Can enable per-region during events

**Cons**:
- ❌ Requires manual intervention to enable
- ❌ Not truly "on-demand" (still needs configuration)
- ❌ Could forget to enable before event

**Estimated Savings**: 138MB when disabled

**Risk**: LOW - Easy to test and revert

---

### Approach 2: Reverse Proxy On-Demand (Medium Risk, Navigator Enhancement)

**Concept**: Navigator starts Action Cable automatically when first WebSocket connection arrives.

**Implementation**:

1. Remove Action Cable from managed processes:
```ruby
def build_managed_processes_config
  processes = []

  # Action Cable now handled by on-demand reverse proxy
  # (removed from here)

  # Redis still needed for other features
  if ENV['FLY_APP_NAME']
    processes << {
      'name' => 'redis',
      # ... existing config ...
    }
  end

  processes
end
```

2. Add on-demand process configuration:
```ruby
def build_routes_config
  # ... existing code ...

  # Configure Action Cable as on-demand reverse proxy
  routes['reverse_proxies'] << {
    'path' => cable_path,
    'target' => cable_target,
    'websocket' => true,
    'on_demand' => {
      'enabled' => true,
      'command' => 'bundle',
      'args' => ['exec', 'puma', '-p', '28080', 'cable/config.ru'],
      'working_dir' => Rails.root.to_s,
      'env' => {
        'RAILS_ENV' => 'production',
        'RAILS_APP_REDIS' => 'showcase_production',
        'RAILS_APP_DB' => 'action-cable'
      },
      'startup_timeout' => '30s',
      'idle_timeout' => '15m'  # Stop after 15m of no connections
    },
    'headers' => {
      'X-Forwarded-For' => '$remote_addr',
      'X-Forwarded-Proto' => '$scheme',
      'X-Forwarded-Host' => '$host'
    }
  }
end
```

3. Enhance Navigator to support on-demand processes:

**New file**: `navigator/internal/process/ondemand.go`
```go
package process

import (
  "context"
  "log/slog"
  "os/exec"
  "sync"
  "time"
)

// OnDemandProcess manages processes that start on first request
type OnDemandProcess struct {
  Name          string
  Command       string
  Args          []string
  WorkingDir    string
  Env           map[string]string
  StartupTimeout time.Duration
  IdleTimeout    time.Duration

  mu            sync.RWMutex
  cmd           *exec.Cmd
  running       bool
  lastAccess    time.Time
  startChan     chan error
}

// EnsureRunning starts the process if not already running
func (p *OnDemandProcess) EnsureRunning(ctx context.Context) error {
  p.mu.Lock()

  // Update last access time
  p.lastAccess = time.Now()

  // Already running
  if p.running {
    p.mu.Unlock()
    return nil
  }

  // Start process
  slog.Info("Starting on-demand process", "name", p.Name)

  cmd := exec.CommandContext(ctx, p.Command, p.Args...)
  cmd.Dir = p.WorkingDir
  cmd.Env = makeEnv(p.Env)

  if err := cmd.Start(); err != nil {
    p.mu.Unlock()
    return err
  }

  p.cmd = cmd
  p.running = true
  p.startChan = make(chan error, 1)

  // Monitor process
  go func() {
    err := cmd.Wait()
    p.mu.Lock()
    p.running = false
    p.mu.Unlock()

    if err != nil {
      slog.Error("On-demand process exited", "name", p.Name, "error", err)
    }
  }()

  p.mu.Unlock()

  // Wait for startup (port becomes available)
  return p.waitForStartup(ctx)
}

// waitForStartup polls until the process is ready to accept connections
func (p *OnDemandProcess) waitForStartup(ctx context.Context) error {
  ctx, cancel := context.WithTimeout(ctx, p.StartupTimeout)
  defer cancel()

  ticker := time.NewTicker(100 * time.Millisecond)
  defer ticker.Stop()

  for {
    select {
    case <-ctx.Done():
      return fmt.Errorf("startup timeout for %s", p.Name)
    case <-ticker.C:
      // Check if port is accepting connections
      if p.isReady() {
        slog.Info("On-demand process ready", "name", p.Name)
        return nil
      }
    }
  }
}

// CheckIdle stops process if idle timeout exceeded
func (p *OnDemandProcess) CheckIdle() {
  p.mu.RLock()
  idleDuration := time.Since(p.lastAccess)
  running := p.running
  p.mu.RUnlock()

  if running && idleDuration > p.IdleTimeout {
    slog.Info("Stopping idle on-demand process", "name", p.Name, "idle", idleDuration)
    p.Stop()
  }
}

// Stop terminates the process
func (p *OnDemandProcess) Stop() {
  p.mu.Lock()
  defer p.mu.Unlock()

  if !p.running || p.cmd == nil {
    return
  }

  // Send SIGTERM
  if err := p.cmd.Process.Signal(syscall.SIGTERM); err != nil {
    slog.Error("Failed to send SIGTERM to on-demand process", "name", p.Name, "error", err)
  }

  // Wait up to 10 seconds for graceful shutdown
  done := make(chan struct{})
  go func() {
    p.cmd.Wait()
    close(done)
  }()

  select {
  case <-done:
    slog.Info("On-demand process stopped gracefully", "name", p.Name)
  case <-time.After(10 * time.Second):
    slog.Warn("Force killing on-demand process", "name", p.Name)
    p.cmd.Process.Kill()
  }

  p.running = false
  p.cmd = nil
}
```

**Modify**: `navigator/internal/server/proxy.go`
```go
// Before proxying WebSocket request, ensure on-demand process is running
if proxyConfig.OnDemand != nil && proxyConfig.OnDemand.Enabled {
  if err := h.onDemandManager.EnsureRunning(r.Context(), proxyConfig.OnDemand); err != nil {
    http.Error(w, "Service unavailable", http.StatusServiceUnavailable)
    return
  }
}

// Continue with normal proxy logic...
```

**Pros**:
- ✅ Truly automatic - no manual intervention needed
- ✅ Saves memory when not in use
- ✅ Automatically stops after idle timeout
- ✅ User-friendly (transparent startup)

**Cons**:
- ❌ Requires Navigator enhancement (new feature)
- ❌ 2-3 second delay on first WebSocket connection
- ❌ Complexity in Navigator code
- ❌ Need to handle startup failures gracefully

**Estimated Savings**: 138MB when not in use

**Risk**: MEDIUM - Requires Navigator changes and thorough testing

---

## Recommendation

**Phase 1 (Immediate)**: Implement **Approach 1** - Make Action Cable optional
- Simple environment variable control
- Can enable per-region for upcoming events
- Immediate 138MB savings for most machines
- Low risk, easy to test and revert

**Phase 2 (Future)**: Implement **Approach 2** after Phase 1 proves successful
- Truly automatic on-demand startup
- Best user experience (transparent, no manual intervention)
- Requires Navigator enhancement

---

## Testing Plan

### Phase 1 Testing (Optional Action Cable)

1. **Verify Action Cable disabled by default**:
```bash
fly ssh console -a smooth-nav -C "ps auxww | grep puma"
# Should show: Navigator, no Action Cable
```

2. **Enable Action Cable**:
```bash
fly secrets set ENABLE_ACTION_CABLE=true -a smooth-nav
fly deploy -a smooth-nav
```

3. **Verify Action Cable starts**:
```bash
fly ssh console -a smooth-nav -C "ps auxww | grep puma"
# Should show: Navigator + Action Cable on port 28080
```

4. **Test WebSocket functionality**:
- Navigate to live scoring interface
- Verify scores update in real-time
- Check console output streaming
- Test current heat updates

5. **Measure memory savings**:
```bash
# With Action Cable disabled
fly ssh console -a smooth-nav -C "ps auxww" | grep -E 'navigator|puma|redis'

# With Action Cable enabled
fly ssh console -a smooth-nav -C "ps auxww" | grep -E 'navigator|puma|redis'
```

### Success Criteria

- ✅ Action Cable doesn't start when `ENABLE_ACTION_CABLE` is unset or false
- ✅ Action Cable starts successfully when `ENABLE_ACTION_CABLE=true`
- ✅ WebSocket connections work correctly when enabled
- ✅ Memory savings of ~138MB verified when disabled
- ✅ No errors in Navigator logs

---

## Implementation Steps (Phase 1)

### Step 1: Update Configurator (5 minutes)

**File**: `app/controllers/concerns/configurator.rb`

```ruby
def build_managed_processes_config
  # Managed processes for production environments
  # This can be customized based on your needs
  processes = []

  # Add standalone Action Cable server (optional)
  # Set ENABLE_ACTION_CABLE=true to enable WebSocket features
  if ENV['ENABLE_ACTION_CABLE'] == 'true'
    processes << {
      'name' => 'action-cable',
      'command' => 'bundle',
      'args' => ['exec', 'puma', '-p', ENV.fetch('CABLE_PORT', '28080'), 'cable/config.ru'],
      'working_dir' => Rails.root.to_s,
      'env' => {
        'RAILS_ENV' => 'production',
        'RAILS_APP_REDIS' => 'showcase_production',
        'RAILS_APP_DB' => 'action-cable'
      },
      'auto_restart' => true,
      'start_delay' => '1s'
    }
  end

  # Add a Redis server if running on Fly.io
  # Redis is always enabled (used for caching, background jobs, etc.)
  if ENV['FLY_APP_NAME']
    processes << {
      'name' => 'redis',
      'command' => 'redis-server',
      'args' => ['/etc/redis/redis.conf'],
      'working_dir' => Rails.root.to_s,
      'env' => {},
      'auto_restart' => true,
      'start_delay' => '2s'
    }
  end

  processes
end
```

### Step 2: Add Documentation (5 minutes)

**File**: `docs/ACTION_CABLE.md`

```markdown
# Action Cable Configuration

Action Cable provides WebSocket support for real-time features:
- Live score updates during judging
- Current heat information displays
- Console output streaming

## Enabling Action Cable

By default, Action Cable is **disabled** to save memory (~138MB).

### Enable for specific events

Set the environment variable before an event:

```bash
fly secrets set ENABLE_ACTION_CABLE=true -a smooth-nav
fly deploy -a smooth-nav
```

### Enable per-region

Use Fly.io's process group overrides in `fly.toml`:

```toml
[env]
  ENABLE_ACTION_CABLE = "false"

[[override.regions.iad]]
  [override.regions.iad.env]
    ENABLE_ACTION_CABLE = "true"
```

### Disable after event

```bash
fly secrets unset ENABLE_ACTION_CABLE -a smooth-nav
fly deploy -a smooth-nav
```

## Verifying Status

Check if Action Cable is running:

```bash
fly ssh console -a smooth-nav -C "ps auxww | grep puma"
```

Expected output with Action Cable enabled:
- Process with `cable/config.ru` on port 28080

Expected output with Action Cable disabled:
- No cable/config.ru process
```

### Step 3: Test Locally (15 minutes)

1. Run without Action Cable:
```bash
unset ENABLE_ACTION_CABLE
bin/rails nav:config
bin/nav
```

2. Verify Action Cable not in config:
```bash
grep -A5 "managed_processes" config/navigator.yml
# Should show only redis, not action-cable
```

3. Run with Action Cable:
```bash
export ENABLE_ACTION_CABLE=true
bin/rails nav:config
bin/nav
```

4. Verify Action Cable in config:
```bash
grep -A5 "managed_processes" config/navigator.yml
# Should show both redis and action-cable
```

5. Test WebSocket connection:
```bash
# Open Rails console
bin/rails c
```

### Step 4: Deploy and Test (30 minutes)

1. Deploy to staging region:
```bash
fly deploy -a smooth-nav --region iad
```

2. Verify Action Cable is NOT running:
```bash
fly ssh console -a smooth-nav -r iad -C "ps auxww"
```

3. Enable Action Cable:
```bash
fly secrets set ENABLE_ACTION_CABLE=true -a smooth-nav --stage
fly deploy -a smooth-nav --region iad
```

4. Verify Action Cable IS running:
```bash
fly ssh console -a smooth-nav -r iad -C "ps auxww | grep cable"
```

5. Test WebSocket features (requires accessing application)

6. Measure memory savings:
```bash
# Before (with Action Cable)
fly ssh console -a smooth-nav -r iad -C "ps auxww | grep puma"

# After (without Action Cable)
fly secrets unset ENABLE_ACTION_CABLE -a smooth-nav --stage
fly deploy -a smooth-nav --region iad
fly ssh console -a smooth-nav -r iad -C "ps auxww"
```

### Step 5: Update Plans Document (5 minutes)

Update `plans/MEMORY_OPTIMIZATION_PLAN.md` with results.

---

## Rollback Plan

If issues arise:

1. Re-enable Action Cable immediately:
```bash
fly secrets set ENABLE_ACTION_CABLE=true -a smooth-nav
fly deploy -a smooth-nav
```

2. Or revert the code change:
```bash
git revert <commit-hash>
git push
fly deploy -a smooth-nav
```

---

## Future Enhancements (Phase 2+)

After Phase 1 is successful and stable:

1. **Automatic enablement** - Implement Approach 2 or 3
2. **Action Cable pooling** - Share one Action Cable across multiple regions
3. **WebSocket health checks** - Monitor connection counts
4. **Graceful degradation** - Fallback to polling if WebSockets unavailable
5. **Action Cable optimization** - Reduce memory of Action Cable itself (see MEMORY_OPTIMIZATION_PLAN.md)

---

## Success Metrics

**Memory Savings**:
- Baseline (no tenants): 169MB → 31MB (138MB saved, 82% reduction)
- Per-region savings: 138MB × 8 regions = 1.1GB total potential savings

**Performance Impact**:
- Static page load: No change (Action Cable not involved)
- WebSocket connection (when disabled): Not available
- WebSocket connection (when enabled): No change

**Operational Impact**:
- Deployment complexity: Minimal (1 environment variable)
- Event preparation: Add "enable Action Cable" to checklist
- Memory budget: 138MB per region becomes available for tenant Rails apps
