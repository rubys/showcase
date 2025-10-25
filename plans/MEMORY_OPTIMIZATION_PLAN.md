# Memory Optimization Plan for Navigator Multi-Tenant Deployment

## Overview - Current State (After Completed Optimizations)

**Measured on smooth-nav with 1 active tenant:**
- **Baseline memory (0 tenants)**: ~372MB (down from initial 397MB)
- **Per-tenant memory**: ~250-350MB per Rails process (estimated, needs measurement)
- **Architecture**: Navigator spawns one Rails process per active tenant
- **Optimizations enabled**: jemalloc via `LD_PRELOAD`

**Baseline breakdown (372MB total):**
1. **Action Cable Puma server** - 152MB (41%) - Primary optimization target
2. **Navigator Go binary** - 17MB (4.5%)
3. **Redis server** - 14MB (3.8%)
4. **System overhead** - ~189MB (51%) - Fly.io hallpass, kernel, etc.

**Per-tenant breakdown (estimated ~250-350MB each):**
1. Ruby VM - ~20-40MB
2. Rails framework - ~80-120MB
3. Application code - ~30-50MB
4. Loaded gems - ~60-100MB
5. Thread overhead (5 threads) - ~50-75MB
6. Connection pools - ~10-20MB

---

## Completed Optimizations

### 1. AWS SDK Removal from nav_startup.rb (Actual: 13MB savings)

**Problem**: `script/nav_startup.rb` loaded `aws-sdk-s3` at startup and kept it resident, even though AWS is only needed once during initialization.

**Solution**: Removed `require 'aws-sdk-s3'` from nav_startup.rb. The sync_databases_s3.rb script already loads it when needed.

**Results**:
- Before: ruby nav_startup.rb = 38MB RSS
- After: ruby nav_startup.rb = 25MB RSS
- **Savings: 13MB (35% reduction in process memory)**

**Status**: ✅ Deployed to production, measured on smooth-nav

### 2. Navigator Hook-Based Startup (Actual: 26MB savings)

**Problem**: nav_startup.rb stayed resident for container lifetime (25MB) just to spawn navigator and run initialization.

**Solution**: Made Navigator the main process using ready hooks for initialization:
- Navigator starts with maintenance config (shows 503.html during init)
- Ready hook executes `script/nav_initialization.rb` with 5-minute timeout
- After successful hook, Navigator auto-reloads with full config
- Initialization script runs once and exits (no persistent process)

**Implementation**:
- Created `config/navigator-maintenance.yml` with ready hook
- Created `script/nav_initialization.rb` (extracted from nav_startup.rb)
- Updated Dockerfile.nav CMD to run Navigator directly
- Enhanced Navigator to support `reload_config` field in hooks

**Results** (measured with 1 active tenant):
- Before: nav_startup.rb = 25MB, navigator = 18MB
- After: nav_startup.rb = 0MB (eliminated), navigator = 17MB
- **Savings: 26MB total (25MB wrapper elimination + 1MB navigator efficiency)**

**Architecture benefits**:
- Cleaner: Navigator is now PID 1 (main process)
- Better signal handling: No signal forwarding needed
- User-friendly: Maintenance page during initialization
- Memory efficient: Ruby initialization runs once and exits

**Status**: ✅ Deployed to production, verified on smooth-nav

---

## Rejected Approaches

### AnyCable (Tested: +35MB WORSE)

**Hypothesis**: Replace 159MB Puma Action Cable server with efficient Go WebSocket server + minimal RPC server.

**Implementation**:
- Added anycable-rails gem and anycable-go binary
- Configured two processes: anycable-go (port 28080) + anycable-rpc (port 50051 gRPC)
- Expected: Go server ~10MB + minimal RPC ~40MB = 50MB total vs 159MB Puma

**Actual Results** (measured on smooth-nav):
- anycable-go: 26MB (higher than expected 5-10MB)
- anycable-rpc: 168MB (expected ~40MB, but loads full Rails environment!)
- **Total: 194MB vs 159MB Puma = +35MB WORSE**

**Root Cause**: AnyCable RPC server loads entire Rails environment (`config/environment.rb`) to handle authentication and subscription logic. While our channels don't access models, the RPC server still needs full Rails framework loaded.

**Conclusion**: AnyCable is designed for **performance and scalability** (handling thousands of concurrent WebSocket connections), NOT for memory reduction. The Go WebSocket server is efficient, but the Rails RPC server negates any savings.

**When AnyCable would help**: High concurrent WebSocket count (1000+ connections), better CPU efficiency, horizontal scaling.

**When AnyCable doesn't help**: Memory reduction (our primary goal).

**Status**: ❌ Tested and rejected, not merged to main

---

## Future Optimization Opportunities

### Baseline Optimizations

#### Priority 1: Action Cable Eager Loading (Estimated: 30-40MB)

**Current**: Action Cable server loads entire Rails environment via `Rails.application.eager_load!`

**Opportunity**: Remove eager loading - channels are pure message relays with no model access.

**Implementation** (cable/config.ru):
```ruby
require_relative "../config/environment"
# Rails.application.eager_load!  ← REMOVE THIS LINE
```

**Risk**: LOW - Channels don't access models, just relay messages
- ScoresChannel, CurrentHeatChannel, OfflinePlaylistChannel: Just `stream_from`
- OutputChannel: Uses Rails.root, Rails.logger, PTY, YAML (all safe)

**Testing**: Test all 4 channels with concurrent WebSocket connections

#### Priority 2: Action Cable Thread Reduction (Estimated: 10-20MB)

**Current**: Action Cable Puma uses default 5 threads

**Opportunity**: Reduce to 1-2 threads (WebSocket connections are long-lived)

**Implementation** (app/controllers/concerns/configurator.rb line 592):
```ruby
'args' => ['exec', 'puma', '-t', '1:2', '-p', ENV.fetch('CABLE_PORT', '28080'), 'cable/config.ru']
```

**Risk**: LOW - Load test with multiple concurrent connections

**Combined savings**: 40-60MB baseline reduction (Options 1+2)

#### Priority 3: Minimal Action Cable Server (Estimated: 100-120MB, ADVANCED)

**Current**: Action Cable loads full Rails (ActiveRecord, ActionView, etc.)

**Opportunity**: Create standalone server with minimal Rails stub

**Implementation**: Replace `cable/config.ru` with minimal dependencies:
- Load only: ActionCable, Redis adapter, channel classes
- Stub: Rails.root, Rails.logger, Rails.env
- Remove: ActiveRecord, ActiveStorage, ActionMailer, all controllers/models

**Risk**: MEDIUM - More complex but viable since channels are simple
- Requires thorough testing of all channels
- OutputChannel PTY/YAML operations need validation

**Consider if**: Options 1+2 don't provide enough savings

#### Priority 4: Aggressive jemalloc Tuning (Estimated: 10-30MB)

**Current**: Conservative jemalloc settings

**Opportunity**: More aggressive memory return to OS for idle processes

**Implementation** (Dockerfile.nav):
```dockerfile
MALLOC_CONF="dirty_decay_ms:1000,muzzy_decay_ms:1000,narenas:2"
```

**Risk**: LOW-MEDIUM - May impact performance under heavy load

#### Priority 5: Redis Memory Limits (Estimated: 5-10MB)

**Current**: Redis at 14MB (already small)

**Opportunity**: Set maxmemory limits

**Implementation** (Dockerfile.nav):
```dockerfile
echo "maxmemory 50mb" >> /etc/redis/redis.conf
echo "maxmemory-policy allkeys-lru" >> /etc/redis/redis.conf
```

### Per-Tenant Optimizations

**CRITICAL**: These multiply by tenant count!
- 5 tenants × 100MB savings = 500MB total
- 10 tenants × 100MB savings = 1GB total

#### Priority 1: Disable Unused Rails Components (Estimated: 50-100MB per tenant)

**Current**: Loading full Rails stack with `require "rails/all"`

**Opportunity**: Selectively require only needed components

**Implementation** (config/application.rb):
```ruby
# Instead of: require "rails/all"
require "rails"
%w(
  active_record/railtie
  action_controller/railtie
  action_view/railtie
  action_cable/engine
).each do |railtie|
  require railtie
end
```

**Investigation needed**: Determine if Active Storage is used (10-20MB potential savings)

#### Priority 2: Reduce Thread Count (Estimated: 20-30MB per tenant)

**Current**: 5 threads per tenant Rails process

**Opportunity**: Reduce to 2 threads (Navigator handles concurrency across processes)

**Implementation** (config/puma.rb or via Navigator config):
```ruby
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 2 }
```

**Trade-off**: Lower per-process concurrency (mitigated by Navigator spawning multiple processes)

#### Priority 3: Disable Eager Loading (Estimated: 20-40MB per tenant)

**Current**: `config.eager_load = true` loads all classes upfront

**Opportunity**: Use lazy loading - trades slightly slower first request for lower memory

**Implementation** (config/environments/production.rb):
```ruby
config.eager_load = false
```

**Trade-off**: First request to each controller ~50-100ms slower as classes load on demand

#### Priority 4: Remove Unused Gems (Estimated: 30-60MB per tenant)

**Investigation needed** - determine if these gems are used:
- **geocoder** (~5-10MB) - geolocation needed?
- **combine_pdf** (~10MB) - PDF generation used?
- **fast_excel** (~5-10MB) - Excel export used?
- **sentry-ruby/sentry-rails** (~10MB) - error tracking worth the memory cost?

**Method**: `grep -r "GemName" app/ lib/` to check usage

#### Priority 5: Reduce Log Level (Estimated: 5-10MB per tenant)

**Current**: Debug logging

**Opportunity**: Use :info or :warn level

**Implementation** (config/environments/production.rb):
```ruby
config.log_level = :info  # or :warn
```

#### Priority 6: Optimize Connection Pool (Estimated: 5-10MB per tenant)

**Current**: Pool size may not match thread count

**Opportunity**: Match pool to threads

**Implementation** (config/database.yml):
```yaml
production:
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 2 } %>
```

---

## Implementation Strategy

### Recommended Approach

**Phase 1: Quick Baseline Wins (This Week)**
1. Action Cable eager loading removal (30-40MB)
2. Action Cable thread reduction (10-20MB)
3. Redis memory limits (5-10MB)
4. **Total: ~45-70MB baseline savings**

**Phase 2: Per-Tenant Optimizations (Next Sprint)**
1. Disable unused Rails components (50-100MB × tenant count)
2. Reduce thread counts (20-30MB × tenant count)
3. Audit and remove unused gems (30-60MB × tenant count)
4. **Total: ~100-190MB per tenant savings**

**Phase 3: Advanced Baseline (If Needed)**
1. Minimal Action Cable server (additional 60-80MB baseline)
2. Aggressive jemalloc tuning (10-30MB baseline)
3. **Total: additional 70-110MB baseline savings**

### Priority Order by Impact

1. **Per-tenant Rails optimizations** - HIGHEST IMPACT (multiplies by tenant count!)
2. **Action Cable eager loading removal** - Easy, low-risk, immediate 30-40MB
3. **Thread reductions** - Both baseline and per-tenant benefits
4. **Gem audit and removal** - Significant per-tenant savings
5. **Advanced optimizations** - Only if quick wins insufficient

---

## Expected Results

### Conservative Estimate (Phase 1 + Phase 2 easy wins)

**Baseline**: 372MB → 317MB (15% reduction, 55MB saved)
- Action Cable optimizations: -50MB
- Redis tuning: -5MB

**Per-tenant**: 300MB → 200MB (33% reduction, 100MB saved per tenant)
- Rails component optimization: -60MB
- Thread reduction: -25MB
- Log level reduction: -5MB
- Connection pool optimization: -10MB

**10 tenants total**: 3,372MB → 2,317MB (31% reduction, 1,055MB saved)

### Aggressive Estimate (All phases)

**Baseline**: 372MB → 257MB (31% reduction, 115MB saved)
- Action Cable optimizations: -50MB
- Minimal Action Cable server: -60MB (if Phase 1 not enough)
- Redis tuning: -5MB

**Per-tenant**: 300MB → 150MB (50% reduction, 150MB saved per tenant)
- Full Rails optimization: -150MB

**10 tenants total**: 3,372MB → 1,757MB (48% reduction, 1,615MB saved)

---

## Measurement and Validation

### Baseline Memory Measurement

```bash
# SSH to Fly.io container
fly ssh console -a smooth-nav

# Check processes
ps aux --sort=-%mem | grep -E "(ruby|navigator|redis|puma)"

# Total memory
free -h
```

### Per-Tenant Memory Measurement

```bash
# Measure with N tenants
# Expected: baseline + (N × per-tenant memory)

# Track over time
watch -n 60 'ps aux --sort=-%mem | head -20'
```

### Performance Validation

```bash
# Full test suite
bin/rails test
bin/rails test:system

# Load testing
# (Define tenant load test strategy)
```

---

## Success Criteria

### Phase 1 Complete When:
- [ ] Baseline memory < 320MB
- [ ] All tests passing
- [ ] WebSocket functionality verified
- [ ] No performance degradation

### Phase 2 Complete When:
- [ ] Per-tenant memory < 200MB
- [ ] All features tested
- [ ] Production smoke test successful
- [ ] 10-tenant scenario measured

### Phase 3 Complete When:
- [ ] Baseline memory < 260MB
- [ ] Per-tenant memory < 150MB
- [ ] System stable under load
- [ ] Memory usage predictable

---

## Rollback Plan

Each optimization:
- Committed separately
- Tested independently
- Easily revertable via `git revert <commit-hash>`

---

## Notes

- **Multi-tenant architecture**: Per-tenant optimizations multiply by active tenant count
- **Trade-offs**: Some optimizations (lazy loading, fewer threads) may slightly impact performance
- **Testing critical**: Each change validated with full test suite
- **Incremental approach**: Start conservative, measure, then optimize further
- **Already completed**: 39MB baseline savings (AWS SDK + Navigator hook startup)

---

## References

- Ruby memory profiling: https://github.com/tmm1/stackprof
- Rails memory optimization: https://www.speedshop.co/2017/12/04/malloc-doubles-ruby-memory.html
- jemalloc tuning: https://github.com/jemalloc/jemalloc/wiki/Getting-Started
- Navigator documentation: navigator/docs/
