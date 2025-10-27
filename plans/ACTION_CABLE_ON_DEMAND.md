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

**Phase 2 (Next)**: Optimize Action Cable memory usage when enabled
- Remove eager loading (30-40MB savings)
- Reduce thread count (10-20MB savings)
- Add Redis memory limits (5-10MB savings)
- **Total: 45-70MB savings when Action Cable is enabled**
- Low risk, complements Phase 1

**Phase 3 (Future)**: Implement **Approach 2** - Automatic on-demand startup
- Truly automatic on-demand startup
- Best user experience (transparent, no manual intervention)
- Requires Navigator enhancement

---

## Phase 2 Implementation: Action Cable Memory Optimization

When Action Cable is enabled, optimize its memory footprint from 152MB to ~82-107MB.

### Optimization 1: Remove Eager Loading (30-40MB savings)

**Problem**: Action Cable loads entire Rails environment via `Rails.application.eager_load!`

**Analysis**: Our Action Cable channels are pure message relays:
- `ScoresChannel`, `CurrentHeatChannel`, `OfflinePlaylistChannel`: Just `stream_from`
- `OutputChannel`: Uses Rails.root, Rails.logger, PTY, YAML (all safe)
- **No model access required**

**Implementation**:

**File**: `cable/config.ru`

```ruby
require_relative "../config/environment"
# Rails.application.eager_load!  ← REMOVE THIS LINE
```

**Risk**: LOW - Channels don't access models or require eager-loaded classes

**Testing**:
- Test all 4 channels with concurrent WebSocket connections
- Verify real-time score updates work
- Verify console output streaming works
- Verify current heat updates work

---

### Optimization 2: Reduce Thread Count (10-20MB savings)

**Problem**: Action Cable Puma uses default 5 threads, but WebSocket connections are long-lived and don't need many threads.

**Implementation**:

**File**: `app/controllers/concerns/configurator.rb` (around line 614)

**Before**:
```ruby
processes << {
  'name' => 'action-cable',
  'command' => 'bundle',
  'args' => ['exec', 'puma', '-p', ENV.fetch('CABLE_PORT', '28080'), 'cable/config.ru'],
  # ...
}
```

**After**:
```ruby
processes << {
  'name' => 'action-cable',
  'command' => 'bundle',
  'args' => ['exec', 'puma', '-t', '1:2', '-p', ENV.fetch('CABLE_PORT', '28080'), 'cable/config.ru'],
  # ...
}
```

**Risk**: LOW - WebSocket connections are long-lived, minimal concurrency needed

**Testing**: Load test with multiple concurrent WebSocket connections (10-20 clients)

---

### Optimization 3: Redis Memory Limits (5-10MB savings)

**Problem**: Redis at 14MB with no memory limits

**Implementation**:

**File**: `Dockerfile.nav` (after line 106)

**Add**:
```dockerfile
# configure redis
RUN sed -i 's/^daemonize yes/daemonize no/' /etc/redis/redis.conf &&\
  sed -i 's/^bind/# bind/' /etc/redis/redis.conf &&\
  sed -i 's/^protected-mode yes/protected-mode no/' /etc/redis/redis.conf &&\
  sed -i 's/^logfile/# logfile/' /etc/redis/redis.conf &&\
  echo "vm.overcommit_memory = 1" >> /etc/sysctl.conf &&\
  echo "maxmemory 50mb" >> /etc/redis/redis.conf &&\
  echo "maxmemory-policy allkeys-lru" >> /etc/redis/redis.conf
```

**Risk**: LOW - 50MB is sufficient for Action Cable message queueing

**Testing**:
- Monitor Redis memory usage under load
- Verify no eviction warnings in Redis logs

---

### Combined Phase 2 Benefits

**Before (Phase 1 only)**:
- Action Cable disabled: 0MB (169MB baseline - 138MB savings)
- Action Cable enabled: 152MB

**After (Phase 1 + Phase 2)**:
- Action Cable disabled: 0MB
- Action Cable enabled: 82-107MB (45-70MB savings)

**Total optimization**:
- When disabled: 138MB saved (vs always-on baseline)
- When enabled: 45-70MB saved (vs original enabled state)

---

## Testing Plan

### Combined Phase 1 + Phase 2 Testing

Test both optional startup AND optimizations together in a single cycle.

#### Step 1: Verify Action Cable Disabled by Default

```bash
# Wake the machine
curl -I https://smooth-nav.fly.dev/

# Check processes (Action Cable should NOT be running)
fly ssh console -a smooth-nav -C "ps auxww"
```

**Expected**: Navigator + Redis only, no Action Cable process

#### Step 2: Measure Baseline Memory (No Action Cable)

```bash
fly ssh console -a smooth-nav -C "ps auxww" > /tmp/phase1-disabled.txt
grep -E 'navigator|redis' /tmp/phase1-disabled.txt
```

**Expected**: ~31MB total (Navigator 17MB + Redis 14MB)

#### Step 3: Enable Action Cable with Optimizations

```bash
fly secrets set ENABLE_ACTION_CABLE=true -a smooth-nav
fly deploy -a smooth-nav
```

**Note**: This deployment includes Phase 2 optimizations (eager loading removed, threads reduced, Redis limits).

#### Step 4: Verify Optimized Action Cable Starts

```bash
# Wake the machine
curl -I https://smooth-nav.fly.dev/

# Check processes
fly ssh console -a smooth-nav -C "ps auxww"
```

**Expected**: Navigator + Redis + Action Cable (optimized)

#### Step 5: Measure Memory with Optimized Action Cable

```bash
fly ssh console -a smooth-nav -C "ps auxww" > /tmp/phase2-enabled-optimized.txt
grep -E 'navigator|puma|redis' /tmp/phase2-enabled-optimized.txt
```

**Expected**:
- Navigator: ~17MB
- Redis: ~9MB (with 50MB limit, down from 14MB)
- Action Cable: ~82-107MB (down from 152MB)
- **Total: ~108-133MB** (vs 169MB baseline before Phase 1+2)

#### Step 6: Test WebSocket Functionality

1. **Scores Channel** (live scoring):
   - Navigate to event with active scoring
   - Open scoring interface
   - Verify scores update in real-time as entered
   - Check browser console for WebSocket connection

2. **Current Heat Channel** (display boards):
   - Navigate to event schedule
   - Verify current heat updates automatically
   - Check multiple concurrent connections

3. **Output Channel** (console streaming):
   - Navigate to admin console interface
   - Run a command
   - Verify output streams to browser in real-time

4. **Concurrent Load Test**:
   - Open 10-20 browser tabs to WebSocket features
   - Verify all connections stable
   - Check Action Cable memory doesn't balloon

#### Step 7: Compare Memory Savings

```bash
# Compare the files
echo "=== Baseline (Phase 1+2 disabled) ==="
grep -E 'navigator|redis' /tmp/phase1-disabled.txt | awk '{sum+=$6} END {print "Total: " sum/1024 " MB"}'

echo "=== With optimized Action Cable (Phase 1+2 enabled) ==="
grep -E 'navigator|puma|redis' /tmp/phase2-enabled-optimized.txt | awk '{sum+=$6} END {print "Total: " sum/1024 " MB"}'
```

**Expected Savings**:
- Phase 1 (disabled): 138MB saved vs original baseline
- Phase 2 (enabled + optimized): 45-70MB saved vs original enabled state

### Success Criteria

**Phase 1 (Optional Startup)**:
- ✅ Action Cable doesn't start when `ENABLE_ACTION_CABLE` is unset or false
- ✅ Action Cable starts successfully when `ENABLE_ACTION_CABLE=true`
- ✅ Memory savings of ~138MB verified when disabled

**Phase 2 (Optimizations)**:
- ✅ Action Cable memory reduced from 152MB to 82-107MB when enabled
- ✅ Redis memory reduced from 14MB to ~9MB
- ✅ All 4 WebSocket channels work correctly
- ✅ No errors in Navigator logs
- ✅ Concurrent connections stable (10-20 clients)

**Combined**:
- ✅ Total baseline memory: 169MB → 31MB when disabled (138MB saved)
- ✅ Total baseline memory: 169MB → 108-133MB when enabled (36-61MB saved)

---

## Implementation Steps (Phase 1 + Phase 2 Combined)

### Step 1: Update Configurator for Optional + Optimized Action Cable (5 minutes)

**File**: `app/controllers/concerns/configurator.rb`

**Changes**:
1. Wrap Action Cable in `ENV['ENABLE_ACTION_CABLE'] == 'true'` check (Phase 1)
2. Add `-t 1:2` thread reduction to puma args (Phase 2)

```ruby
def build_managed_processes_config
  # Managed processes for production environments
  # This can be customized based on your needs
  processes = []

  # Add standalone Action Cable server (optional)
  # Set ENABLE_ACTION_CABLE=true to enable WebSocket features
  # When enabled, uses optimized settings for memory efficiency
  if ENV['ENABLE_ACTION_CABLE'] == 'true'
    processes << {
      'name' => 'action-cable',
      'command' => 'bundle',
      'args' => ['exec', 'puma', '-t', '1:2', '-p', ENV.fetch('CABLE_PORT', '28080'), 'cable/config.ru'],
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

### Step 2.5: Remove Action Cable Eager Loading (2 minutes) - Phase 2

**File**: `cable/config.ru`

Comment out the eager loading line:

```ruby
require_relative "../config/environment"
# Rails.application.eager_load!  ← REMOVE or COMMENT THIS LINE
run ActionCable.server
```

### Step 2.6: Add Redis Memory Limits (2 minutes) - Phase 2

**File**: `Dockerfile.nav` (around line 102-106)

Update the Redis configuration section:

```dockerfile
# configure redis
RUN sed -i 's/^daemonize yes/daemonize no/' /etc/redis/redis.conf &&\
  sed -i 's/^bind/# bind/' /etc/redis/redis.conf &&\
  sed -i 's/^protected-mode yes/protected-mode no/' /etc/redis/redis.conf &&\
  sed -i 's/^logfile/# logfile/' /etc/redis/redis.conf &&\
  echo "vm.overcommit_memory = 1" >> /etc/sysctl.conf &&\
  echo "maxmemory 50mb" >> /etc/redis/redis.conf &&\
  echo "maxmemory-policy allkeys-lru" >> /etc/redis/redis.conf
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

## Future Enhancements (Phase 3+)

After Phase 1+2 are successful and stable:

1. **Automatic on-demand startup** - Implement Approach 2 (Navigator enhancement)
2. **Action Cable pooling** - Share one Action Cable across multiple regions
3. **WebSocket health checks** - Monitor connection counts
4. **Graceful degradation** - Fallback to polling if WebSockets unavailable
5. **Further Action Cable optimization** - Minimal server approach (see MEMORY_OPTIMIZATION_PLAN.md)

---

## Success Metrics

**Phase 1+2 Memory Savings**:
- Baseline (no tenants, disabled): 169MB → 31MB (138MB saved, 82% reduction)
- Baseline (no tenants, enabled + optimized): 169MB → 108-133MB (36-61MB saved, 21-36% reduction)
- Per-region savings (disabled): 138MB × 8 regions = 1.1GB total
- Per-region savings (enabled): 45-70MB × 8 regions = 360-560MB total

**Performance Impact**:
- Static page load: No change (Action Cable not involved)
- WebSocket connection (when disabled): Not available
- WebSocket connection (when enabled + optimized): No change expected
- Cold start with Action Cable: Slightly faster (less memory to allocate)

**Operational Impact**:
- Deployment complexity: Minimal (1 environment variable)
- Event preparation: Add "enable Action Cable" to checklist
- Memory budget: 138MB per region becomes available for tenant Rails apps (when disabled)
- Memory budget: 45-70MB per region becomes available even when enabled (Phase 2 optimizations)
