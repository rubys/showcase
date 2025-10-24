# Memory Optimization Plan for Navigator Multi-Tenant Deployment

## Current State
- **Baseline memory (0 tenants)**: ~397MB on Fly.io (measured on smooth-nav)
- **Per-tenant memory**: ~250-350MB per Rails process (estimated)
- **Architecture**: Navigator spawns one Rails process per active tenant
- **Current optimizations**: jemalloc enabled via `LD_PRELOAD`

## Goals
- Reduce baseline memory usage to ~200-250MB (35-50% reduction)
- Reduce per-tenant memory to ~150-200MB (30-50% reduction)
- Maintain application functionality and performance
- Optimize for the multi-tenant process model

## Memory Architecture Understanding

### Baseline (0 tenants) - 397MB ✅ MEASURED on smooth-nav

**Actual memory usage from `fly ssh console -a smooth-nav`:**

```
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root       695  0.3  7.8 915504 158756 ?       Sl   16:31   0:02 puma 7.1.0 (tcp://0.0.0.0:28080) [rails]
root       659  0.0  1.9 502476 38360 ?        Sl   16:31   0:00 ruby /rails/script/nav_startup.rb
root       658  0.0  0.9 1244844 20120 ?       Sl   16:31   0:00 /.fly/hallpass
root       670  0.0  0.9 1393532 19688 ?       Sl   16:31   0:00 navigator
root       696  0.2  0.6  69256 13568 ?        Sl   16:31   0:02 redis-server *:6379
```

**Breakdown:**
1. **Action Cable Puma server** - **159MB (40% of baseline!)** ⭐ HIGHEST IMPACT
   - Standalone Action Cable server shared by all tenants
   - Loads entire Rails environment + eager_load!
   - Runs on port 28080
2. **Ruby startup script** (nav_startup.rb) - **38MB (10%)**
   - Stays resident as parent process
   - Loads aws-sdk-s3 at startup (~30MB of this)
3. **Fly.io hallpass** - **20MB (5%)**
   - Fly.io authentication/proxy (not present in local deployments)
4. **Navigator Go binary** - **20MB (5%)**
   - Very efficient!
5. **Redis server** - **14MB (3.5%)**
   - Already quite small
6. **System overhead** - **~146MB (37%)**
   - Init process, kernel threads, etc.

**Key findings:**
- 74 tenant databases available in `/data/db/`
- 0 active tenant Rails processes running
- Total container memory: 1.9GB, used: 397MB, available: 1.5GB

### Per-Tenant (each Rails process) - ~250-350MB
1. **Ruby VM** - ~20-40MB
2. **Rails framework** - ~80-120MB
3. **Application code** - ~30-50MB
4. **Loaded gems** - ~60-100MB
5. **Thread overhead** (5 threads × 10-15MB) - ~50-75MB
6. **Connection pools** - ~10-20MB
7. **jemalloc overhead** - ~10-20MB

---

## Section 1: Baseline Memory Optimization

### Priority 1: Optimize Action Cable Server ⭐ HIGHEST IMPACT (Estimated savings: 30-100MB)

**Current state**: 159MB (40% of baseline memory!)

**Issue**: The standalone Action Cable server loads the entire Rails application unnecessarily.

**Location**: `cable/config.ru` lines 4-5:
```ruby
require_relative "../config/environment"
Rails.application.eager_load!
```

This loads:
- All models, controllers, helpers, concerns
- All gems from Gemfile (ActiveRecord, ActiveStorage, ActionMailer, etc.)
- Full Rails framework
- Application code that Action Cable doesn't need

**Action Cable only needs**:
- ActionCable framework itself
- Redis connection
- Channel classes (app/channels/)
- Connection authentication logic

#### Option A: Remove Eager Loading (EASY, LOW RISK, 30-40MB savings)

Simply remove the eager loading to let classes load on-demand:

```ruby
# cable/config.ru
require_relative "../config/environment"
# Rails.application.eager_load!  ← REMOVE THIS LINE
```

**Expected savings**: 30-40MB
**Risk**: Low - classes load on-demand when needed
**Testing**: Verify WebSocket connections work for all channels

#### Option B: Selective Loading (ADVANCED, HIGH RISK, 80-100MB savings)

Create minimal boot environment that only loads what Action Cable needs:

```ruby
# cable/config.ru - REPLACE ENTIRE FILE
ENV['RAILS_ENV'] ||= 'production'

# Load only what Action Cable needs
require 'bundler/setup'
require 'rails'
require 'action_cable'
require 'redis'

# Minimal Rails setup
module ShowcaseApp
  class Application < Rails::Application
    config.load_defaults 8.0
    config.eager_load = false
  end
end

# Initialize just Action Cable
ActionCable.server.config.cable = {
  adapter: 'redis',
  url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'),
  channel_prefix: ENV.fetch('RAILS_APP_REDIS', 'showcase_production')
}

# Load only channel classes
Dir[File.expand_path('../app/channels/**/*.rb', __dir__)].each { |f| require f }

# Allow all origins (Navigator handles security)
ActionCable.server.config.allowed_request_origins = [/.*/]

map "/cable" do
  run ActionCable.server
end
```

**Expected savings**: 80-100MB
**Risk**: High - need to ensure all dependencies are loaded
**Testing**: Thorough testing of all WebSocket features

#### Option C: Reduce Thread Count (EASY, LOW RISK, 10-20MB savings)

Action Cable server uses default Puma config (5 threads). Reduce threads for WebSocket handling:

```ruby
# In app/controllers/concerns/configurator.rb line 592
# Change from:
'args' => ['exec', 'puma', '-p', ENV.fetch('CABLE_PORT', '28080'), 'cable/config.ru'],

# To:
'args' => ['exec', 'puma', '-t', '1:2', '-p', ENV.fetch('CABLE_PORT', '28080'), 'cable/config.ru'],
```

**Expected savings**: 10-20MB
**Risk**: Low - WebSocket connections are long-lived, don't need many threads
**Testing**: Load test with multiple concurrent WebSocket connections

**Recommendation**: Start with **Option A + Option C** (40-60MB savings) as quick wins, then consider Option B for maximum optimization.

### Priority 2: Remove AWS SDK from nav_startup.rb ✅ IMPLEMENTED (Actual savings: 13.4MB)

**Current state**: 38MB → 25MB resident process

**Issue**: `script/nav_startup.rb` line 4 loaded `aws-sdk-s3` at startup and kept it in memory for the container lifetime, even though AWS is only used once during initialization by `sync_databases_s3.rb` (which already loads aws-sdk-s3 itself).

**Implementation**: ✅ COMPLETED
```ruby
# script/nav_startup.rb lines 3-6
require 'bundler/setup'
# Note: aws-sdk-s3 is loaded by sync_databases_s3.rb when needed, not here
require 'fileutils'
require_relative '../lib/htpasswd_updater'
```

**Rationale**:
- nav_startup.rb stays resident as parent process (line 105: waits for navigator to exit)
- AWS SDK is only needed once at line 74: `system "ruby #{git_path}/script/sync_databases_s3.rb"`
- sync_databases_s3.rb already loads aws-sdk-s3 at its line 7
- No need to keep 30MB gem loaded in parent process forever

**Results from smooth-nav deployment**:
- Before: `ruby nav_startup.rb` = 38MB RSS
- After: `ruby nav_startup.rb` = 25MB RSS
- **Actual savings: 13.4MB (35% reduction in process memory)**

Note: Expected ~30MB savings, but got 13.4MB. The difference may be due to:
- Bundler overhead remaining loaded
- Other shared Ruby VM components
- Still a significant improvement for a one-line change!

**Risk**: Low - sync_databases_s3.rb is a separate process with its own dependencies
**Testing**: ✅ All tests passing (1029 runs, 4782 assertions, 0 failures)
**Production verification**: ✅ Deployed to smooth-nav and measured

**Further optimization possible**: See Priority 2B below for replacing entire Ruby script with shell script.

### Priority 2B: Replace nav_startup.rb with Shell Script (Estimated savings: ~22MB additional)

**Current state**: 25MB resident process (after AWS SDK removal)

**Issue**: The nav_startup.rb script stays resident for the container lifetime, keeping the Ruby VM and bundler loaded in memory (~25MB). The script only needs to:
1. Spawn navigator process
2. Run several Ruby scripts (which can exit after running)
3. Wait for navigator process to exit
4. Handle signals to forward to navigator

**Proposal**: Replace Ruby script with lightweight bash script that calls Ruby scripts as needed.

**Memory comparison**:
- Current Ruby approach: **~25MB** (Ruby VM + bundler + libraries stay resident)
- Shell script approach: **~2-3MB** (bash is minimal, Ruby scripts run and exit)
- **Savings: ~22-23MB (90% reduction in nav_startup process)**

**Implementation**:

Create `script/nav_startup.sh`:
```bash
#!/bin/bash
set -e  # Exit on error

# PIDs to track
NAV_PID=""
PRERENDER_PID=""

# Cleanup function for signal handling
cleanup() {
  echo "Cleaning up processes..."
  if [ -n "$PRERENDER_PID" ]; then
    kill -TERM "$PRERENDER_PID" 2>/dev/null || true
    wait "$PRERENDER_PID" 2>/dev/null || true
  fi
  if [ -n "$NAV_PID" ]; then
    kill -TERM "$NAV_PID" 2>/dev/null || true
    wait "$NAV_PID" 2>/dev/null || true
  fi
  exit 0
}

# Set trap before starting processes
trap cleanup TERM INT EXIT

# Start navigator with maintenance config
cp config/navigator-maintenance.yml config/navigator.yml
navigator &
NAV_PID=$!

# Check for required AWS environment variables
if [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_ENDPOINT_URL_S3" ]; then
  echo "Error: Missing required AWS environment variables"
  exit 1
fi

# Setup directories
git_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -d "/data/db" ] && export RAILS_DB_VOLUME="/data/db"
dbpath="${RAILS_DB_VOLUME:-$git_path/db}"
mkdir -p "$dbpath"
chown rails:rails "$dbpath" 2>/dev/null || true

# Create log directory if needed
if [ -n "$RAILS_LOG_VOLUME" ]; then
  mkdir -p "$RAILS_LOG_VOLUME"
  # Fix ownership if owned by root
  if [ "$(stat -c %u "$RAILS_LOG_VOLUME" 2>/dev/null)" = "0" ]; then
    echo "Fixing ownership of $RAILS_LOG_VOLUME"
    chown -R rails:rails "$RAILS_LOG_VOLUME"
  fi
fi

# Run database sync (Ruby script runs and exits)
ruby "$git_path/script/sync_databases_s3.rb" --index-only --quiet

# Update htpasswd (Ruby script runs and exits)
ruby -r "$git_path/lib/htpasswd_updater.rb" -e "HtpasswdUpdater.update"

# Start prerender in background
bin/prerender &
PRERENDER_PID=$!

# Set cable port for navigator config
export CABLE_PORT=28080

# Generate navigator configuration (Rails task runs and exits)
bin/rails nav:config

# Setup demo directories
mkdir -p /demo/db /demo/storage/demo
chown rails:rails /demo /demo/db /demo/storage/demo 2>/dev/null || true

# Signal navigator to reload with new config
kill -HUP "$NAV_PID"

# Wait for prerender to complete
wait "$PRERENDER_PID"
PRERENDER_PID=""  # Clear so cleanup doesn't try to kill it again

# Fix ownership of inventory.json if needed
inventory_file="$git_path/tmp/inventory.json"
if [ -f "$inventory_file" ] && [ "$(stat -c %u "$inventory_file" 2>/dev/null)" = "0" ]; then
  echo "Fixing ownership of $inventory_file"
  chown rails:rails "$inventory_file"
fi

# Wait for navigator (should never exit in normal operation)
wait "$NAV_PID"
exit $?
```

Update `Dockerfile.nav` CMD to use shell script:
```dockerfile
CMD ["/rails/script/nav_startup.sh"]
```

**Advantages**:
- **~22MB memory savings** (90% reduction in startup script overhead)
- Shell script stays resident at only ~2-3MB instead of 25MB
- Ruby scripts still used for complex logic, but they exit after running
- No Ruby VM stays loaded unnecessarily

**Disadvantages**:
- More verbose signal handling (~15 more lines vs Ruby)
- Need to handle shell script edge cases (error suppression, variable quoting)
- Slightly harder to debug than Ruby (though still straightforward bash)

**Signal Handling Complexity**:
The main difference is that shell scripts require:
- Explicit cleanup function with PID tracking
- Setting trap before spawning processes
- Error suppression (`2>/dev/null || true`) for robustness
- Careful quoting and variable checks

Ruby's signal handling is more elegant but costs 22MB of resident memory.

**Expected savings**: ~22MB baseline reduction
**Risk**: Low-Medium - shell scripting is well-understood, but needs thorough testing
**Testing required**:
- Test signal handling (SIGTERM, SIGINT)
- Test all file ownership operations work
- Test AWS sync and htpasswd update
- Test navigator config generation
- Verify prerender completes successfully

**Recommendation**: Consider this optimization after Action Cable optimizations, as Action Cable has higher ROI (35-100MB potential savings).

### Priority 3: Redis Memory Limits (Estimated savings: 5-10MB)

**Current state**: 14MB (already quite small)

**Implementation**:
```dockerfile
# In Dockerfile.nav, after redis configuration (around line 94-104)
RUN sed -i 's/^daemonize yes/daemonize no/' /etc/redis/redis.conf &&\
  sed -i 's/^bind/# bind/' /etc/redis/redis.conf &&\
  sed -i 's/^protected-mode yes/protected-mode no/' /etc/redis/redis.conf &&\
  sed -i 's/^logfile/# logfile/' /etc/redis/redis.conf &&\
  echo "maxmemory 50mb" >> /etc/redis/redis.conf &&\
  echo "maxmemory-policy allkeys-lru" >> /etc/redis/redis.conf &&\
  echo "vm.overcommit_memory = 1" >> /etc/sysctl.conf
```

**Testing**:
```bash
# After deployment, check Redis memory
redis-cli info memory | grep used_memory_human
```

### Priority 4: Aggressive jemalloc Tuning (Estimated savings: 10-30MB)

**Rationale**: More aggressive memory return to OS for idle processes.

**Implementation**:
```dockerfile
# In Dockerfile.nav, line 110 - add MALLOC_CONF
ENV DATABASE_URL="sqlite3:///data/production.sqlite3" \
    RAILS_DB_VOLUME="/data/db" \
    RAILS_LOG_TO_STDOUT="1" \
    RAILS_LOG_VOLUME="/data/log" \
    RAILS_SERVE_STATIC_FILES="true" \
    RAILS_STORAGE="/data/storage" \
    LD_PRELOAD="/usr/lib/x86_64-linux-gnu/libjemalloc.so.2" \
    MALLOC_CONF="dirty_decay_ms:1000,muzzy_decay_ms:1000,narenas:2"
```

**Options for more aggressive tuning** (test performance impact):
```dockerfile
# Even more aggressive (may impact performance under load)
MALLOC_CONF="dirty_decay_ms:500,muzzy_decay_ms:500,narenas:1,lg_tcache_max:13"
```

**Testing**:
```bash
# Verify jemalloc is loaded
ldd $(which ruby) | grep jemalloc

# Monitor memory usage over time
watch -n 5 'ps aux | grep -E "(redis|navigator|ruby)" | grep -v grep'
```

### Priority 5: Disable Vector if Not Needed (Estimated savings: 10-30MB)

**Current state**: Not visible in process list on smooth-nav (may not be running)

**Rationale**: Vector log aggregation may not be needed for all deployments.

**Investigation needed**:
- Check if Vector process is actually running: `pgrep -a vector`
- Determine if standard logging is sufficient
- Consider making Vector optional via environment variable

**Implementation** (if Vector not needed):
```dockerfile
# In Dockerfile.nav, line 78 - make Vector optional
RUN if [ "$ENABLE_VECTOR" = "true" ]; then \
      bash -c "$(curl -L https://setup.vector.dev)"; \
    fi && \
    apt-get install --no-install-recommends -y dnsutils nats-server poppler-utils procps redis-server ruby-foreman sqlite3 sudo vim unzip && \
    if [ "$ENABLE_VECTOR" = "true" ]; then \
      apt-get install --no-install-recommends -y vector; \
    fi && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
```

---

## Section 2: Per-Tenant Memory Optimization

**CRITICAL**: These optimizations multiply by the number of active tenants!
- 5 tenants × 100MB savings = 500MB total savings
- 10 tenants × 100MB savings = 1GB total savings

### Priority 1: Disable Unused Rails Components ⭐ HIGHEST IMPACT (50-100MB per tenant)

**Rationale**: Loading full Rails stack when only subset is needed.

**Implementation**:
```ruby
# config/application.rb - replace line 3
# Instead of:
require "rails/all"

# Selectively require only what's needed:
require "rails"
%w(
  active_record/railtie
  active_storage/engine
  action_controller/railtie
  action_view/railtie
  action_cable/engine
).each do |railtie|
  begin
    require railtie
  rescue LoadError
  end
end
```

**Optional removals** (investigate if used):
- `active_storage/engine` if file uploads not used (10-20MB)
- `action_cable/engine` if WebSockets not used (15-25MB)

**Testing**:
```bash
# Start Rails console and verify functionality
RAILS_ENV=production bin/rails console

# Test key features:
# - Database queries work
# - Controllers render
# - WebSockets work (if using Action Cable)
```

### Priority 2: Reduce Thread Count (20-30MB per tenant)

**Rationale**: Each thread consumes ~10-15MB. Navigator handles concurrency across processes.

**Implementation**:
```ruby
# config/puma.rb - line 7
# Instead of:
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }

# Use fewer threads:
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 2 }
```

**Alternative**: Set via Navigator tenant configuration:
```yaml
# config/navigator.yml
applications:
  env:
    RAILS_MAX_THREADS: "2"
```

**Testing**:
```bash
# Under light load, verify responsiveness
# Monitor thread count per process
ps -eLf | grep rails | wc -l
```

### Priority 3: Disable Eager Loading (20-40MB per tenant)

**Rationale**: Eager loading loads all classes upfront. Lazy loading trades slightly slower first request for lower memory.

**Implementation**:
```ruby
# config/environments/production.rb - line 14
# Instead of:
config.eager_load = true

# Use lazy loading:
config.eager_load = false
```

**Tradeoff**: First request to each controller will be slightly slower (~50-100ms) as classes load on demand.

**Testing**:
```bash
# Measure first request latency
time curl http://localhost:3000/path/to/endpoint

# Verify functionality across app
bin/rails test
```

### Priority 4: Remove Unused Gems (30-60MB per tenant)

**Rationale**: Every gem loaded into each tenant process.

**Gems to investigate**:
1. **aws-sdk-s3** (~30MB) - Check if S3 used per-tenant or only at startup
2. **geocoder** (~5-10MB) - If geolocation not needed
3. **combine_pdf** (~10MB) - If PDF generation not used
4. **fast_excel** (~5-10MB) - If Excel export not used
5. **sentry-ruby/sentry-rails** (~10MB) - Consider if error tracking worth memory cost

**Investigation**:
```bash
# Find gem usage in codebase
grep -r "Aws::S3" app/ lib/
grep -r "Geocoder" app/ lib/
grep -r "CombinePDF" app/ lib/
grep -r "FastExcel" app/ lib/
```

**Implementation**:
```ruby
# Gemfile - make gems optional or remove
group :optional do
  gem "aws-sdk-s3", "~> 1.176"  # Only if S3 used per-tenant
  gem "geocoder", "~> 1.8"       # Only if geolocation needed
  gem "combine_pdf", "~> 1.0"    # Only if PDF generation used
end
```

**Testing**:
```bash
# After removing gem, run full test suite
bin/rails test
bin/rails test:system
```

### Priority 5: Reduce Log Level (5-10MB per tenant)

**Rationale**: Debug logging consumes memory with log buffers.

**Implementation**:
```ruby
# config/environments/production.rb - line 73
# Instead of:
config.log_level = :debug

# Use:
config.log_level = :info  # or :warn for even less
```

**Testing**:
```bash
# Verify logs still capture important events
tail -f log/production.log
```

### Priority 6: Optimize Database Connection Pool (5-10MB per tenant)

**Rationale**: Connection pool size should match thread count.

**Implementation**:
```yaml
# config/database.yml
production:
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 2 } %>
```

**Testing**:
```bash
# Verify no connection pool exhaustion under load
# Monitor ActiveRecord connection pool stats
```

---

## Implementation Strategy

### Phase 1: Low-Risk Baseline Optimizations (Week 1)
1. ✅ Redis memory limits
2. ✅ jemalloc tuning (conservative settings)
3. ✅ Log level reduction
4. ✅ Thread count reduction

**Expected baseline savings**: 40-80MB
**Expected per-tenant savings**: 30-50MB per tenant

### Phase 2: Rails Component Optimization (Week 2)
1. ✅ Disable unused Rails components
2. ✅ Disable eager loading
3. ✅ Test thoroughly

**Expected per-tenant savings**: 70-140MB per tenant

### Phase 3: Gem Audit and Removal (Week 3)
1. ✅ Audit gem usage
2. ✅ Remove unused gems
3. ✅ Test each removal

**Expected per-tenant savings**: 30-60MB per tenant

### Phase 4: Advanced Optimization (Week 4)
1. ✅ More aggressive jemalloc settings
2. ✅ Ruby startup script optimization
3. ✅ Optional Vector removal
4. ✅ Monitor and tune

**Expected baseline savings**: 30-60MB

---

## Measurement and Validation

### Baseline Memory Measurement
```bash
# With 0 active tenants
docker stats --no-stream showcase-container

# Check individual processes
ps aux --sort=-%mem | head -20
```

### Per-Tenant Memory Measurement
```bash
# With 1 tenant active
# Measure delta from baseline
docker stats --no-stream showcase-container

# With N tenants active
# Should be: baseline + (N × per-tenant memory)
```

### Performance Validation
```bash
# Response time should not significantly degrade
time curl http://localhost:3000/path/to/endpoint

# Run full test suite
bin/rails test
bin/rails test:system

# Load test with multiple tenants
# (Define specific load testing strategy)
```

---

## Expected Results

### Based on Actual Measurements (smooth-nav baseline: 397MB)

### Quick Wins (Action Cable + AWS SDK + Thread reductions)
- **Baseline optimizations**:
  - Action Cable eager_load removal: -35MB (estimated)
  - Action Cable thread reduction: -15MB (estimated)
  - AWS SDK removal: -13MB ✅ (measured on smooth-nav)
  - Redis tuning: -5MB (estimated)
  - **Total baseline savings: ~68MB (updated with actual measurement)**
- **Baseline**: 397MB → 329MB (17% reduction, updated estimate)
- **Per-tenant**: 300MB → 200MB (33% reduction, from Rails optimizations)
- **10 tenants**: 3,397MB → 2,312MB (32% reduction, 1.1GB savings)

### Aggressive Optimizations (Including selective Action Cable loading)
- **Baseline optimizations**:
  - Action Cable selective loading: -90MB
  - Action Cable thread reduction: -15MB
  - AWS SDK lazy loading: -30MB
  - Redis tuning: -5MB
  - jemalloc aggressive tuning: -20MB
  - **Total baseline savings: ~160MB**
- **Baseline**: 397MB → 237MB (40% reduction)
- **Per-tenant**: 300MB → 150MB (50% reduction, from full Rails optimizations)
- **10 tenants**: 3,397MB → 1,737MB (49% reduction, 1.66GB savings)

### Priority Order by Impact:
1. **Action Cable optimization** (35-90MB baseline) ⭐ Highest ROI
2. **Per-tenant Rails optimizations** (100-150MB × tenant count)
3. **AWS SDK lazy loading** (30MB baseline)
4. **Thread reductions** (15MB baseline + 20-30MB × tenant count)
5. **Redis/jemalloc tuning** (5-25MB baseline)

---

## Rollback Plan

Each optimization should be:
1. ✅ Committed separately
2. ✅ Tested independently
3. ✅ Easily revertable via git

**Rollback command**:
```bash
git revert <commit-hash>
```

---

## Success Criteria

### Phase 1 Complete When:
- [ ] Baseline memory < 300MB
- [ ] Per-tenant memory < 250MB
- [ ] All tests passing
- [ ] No performance degradation

### Phase 2 Complete When:
- [ ] Per-tenant memory < 200MB
- [ ] Rails components working correctly
- [ ] WebSockets functional (if used)
- [ ] All features tested

### Phase 3 Complete When:
- [ ] Per-tenant memory < 180MB
- [ ] Removed gems confirmed unused
- [ ] Full test suite passing
- [ ] Production smoke test successful

### Phase 4 Complete When:
- [ ] Baseline memory < 250MB
- [ ] Per-tenant memory < 150MB
- [ ] System stable under load
- [ ] Memory usage predictable

---

## Monitoring Post-Deployment

```bash
# Regular memory checks
watch -n 60 'docker stats --no-stream'

# Track memory over time
docker stats --format "table {{.Name}}\t{{.MemUsage}}" >> memory_log.txt

# Alert on memory spikes
# (Define alerting thresholds)
```

---

## Notes

- **Multi-tenant architecture**: Each optimization to per-tenant memory multiplies by number of active tenants
- **Trade-offs**: Some optimizations (lazy loading, fewer threads) may slightly impact performance
- **Testing critical**: Each change must be validated with full test suite
- **Incremental approach**: Start conservative, measure, then optimize further
- **Production validation**: Test in staging environment with realistic tenant load

---

## References

- Ruby memory profiling: https://github.com/tmm1/stackprof
- Rails memory optimization: https://www.speedshop.co/2017/12/04/malloc-doubles-ruby-memory.html
- jemalloc tuning: https://github.com/jemalloc/jemalloc/wiki/Getting-Started
- Navigator architecture: navigator/CLAUDE.md
