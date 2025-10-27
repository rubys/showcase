# Memory Optimization Plan for Navigator Multi-Tenant Deployment

## Overview - Current State (After Completed Optimizations)

**Measured on smooth-nav:**
- **Baseline memory (0 tenants)**: ~169MB (down from initial 372MB)
- **Per-tenant memory**: ~250-350MB per Rails process (estimated, needs measurement)
- **Architecture**: Navigator spawns one Rails process per active tenant
- **Optimizations enabled**: jemalloc via `LD_PRELOAD`, Docker prerendering

**Baseline breakdown (169MB total):**
1. **Navigator Go binary** - 17MB (10%)
2. **Redis server** - 14MB (8.3%)
3. **System overhead** - ~138MB (82%) - Fly.io hallpass, kernel, etc.
4. **Action Cable Puma server** - 0MB (disabled by default, see ACTION_CABLE_ON_DEMAND.md)

**Per-tenant breakdown (estimated ~250-350MB each):**
1. Ruby VM - ~20-40MB
2. Rails framework - ~80-120MB
3. Application code - ~30-50MB
4. Loaded gems - ~60-100MB
5. Thread overhead (5 threads) - ~50-75MB
6. Connection pools - ~10-20MB

---

## Completed Optimizations

### 1. AWS SDK Removal from nav_startup.rb (13MB savings)

**Problem**: `script/nav_startup.rb` loaded `aws-sdk-s3` at startup and kept it resident, even though AWS is only needed once during initialization.

**Solution**: Removed `require 'aws-sdk-s3'` from nav_startup.rb. The sync_databases_s3.rb script already loads it when needed.

**Results**: 13MB saved (35% reduction in startup script memory)

**Status**: ✅ Deployed to production

### 2. Navigator Hook-Based Startup (26MB savings)

**Problem**: nav_startup.rb stayed resident for container lifetime (25MB) just to spawn navigator and run initialization.

**Solution**: Made Navigator the main process (PID 1) using ready hooks for initialization. Initialization script runs once and exits.

**Results**: 26MB saved (eliminated 25MB wrapper process + 1MB navigator efficiency)

**Status**: ✅ Deployed to production

### 3. Docker Build-Time Prerendering (7.1s cold start improvement)

**Problem**: First request required starting index tenant to render static HTML (5+ seconds delay).

**Solution**: Run prerender during Docker build, bake static HTML into image.

**Results**: Cold start improved from 9.2s to 2.1s (7.1s faster, 77% improvement)

**Status**: ✅ Deployed to production

### 4. Action Cable Optional Startup (138MB savings when disabled)

**Problem**: Action Cable always running, consuming 152MB even when not needed.

**Solution**: Made Action Cable optional via `ENABLE_ACTION_CABLE` environment variable.

**Results**: 138MB saved when disabled (see ACTION_CABLE_ON_DEMAND.md for details)

**Status**: ✅ Plan created, ready to implement

**Total Completed Savings**: 39MB baseline + 7.1s cold start improvement

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

See **ACTION_CABLE_ON_DEMAND.md** for comprehensive Action Cable optimization plan:
- Phase 1: Optional startup (138MB saved when disabled)
- Phase 2: Memory optimizations when enabled (45-70MB saved)
  - Remove eager loading (30-40MB)
  - Reduce threads (10-20MB)
  - Redis memory limits (5-10MB)
- Phase 3: Navigator automatic on-demand (future)

**Additional baseline opportunities:**

#### Aggressive jemalloc Tuning (Estimated: 10-30MB)

**Current**: Conservative jemalloc settings

**Opportunity**: More aggressive memory return to OS for idle processes

**Implementation** (Dockerfile.nav):
```dockerfile
MALLOC_CONF="dirty_decay_ms:1000,muzzy_decay_ms:1000,narenas:2"
```

**Risk**: LOW-MEDIUM - May impact performance under heavy load

### Per-Tenant Optimizations

**CRITICAL**: These multiply by tenant count!

See **PER_TENANT_OPTIMIZATION.md** for comprehensive per-tenant optimization plan:
- Phase 1: Low-risk quick wins (30-50MB per tenant)
  - Reduce thread counts (20-30MB)
  - Optimize connection pool (5-10MB)
  - Reduce log level (5-10MB)
- Phase 2: Gem audit and removal (30-60MB per tenant)
- Phase 3: Advanced optimizations (70-140MB per tenant)
  - Disable unused Rails components (50-100MB)
  - Disable eager loading (20-40MB)

**Expected Results**:
- Conservative: 300MB → 200MB per tenant (33% reduction)
- Aggressive: 300MB → 150MB per tenant (50% reduction)
- 10 tenants: 1-1.5GB total savings

---

## Implementation Strategy

### Recommended Approach

**Next: Action Cable On-Demand (See ACTION_CABLE_ON_DEMAND.md)**
1. Phase 1: Make Action Cable optional (138MB saved when disabled)
2. Phase 2: Optimize when enabled (45-70MB saved when running)
3. **Total: 138MB baseline savings OR 36-61MB when enabled**

**After: Per-Tenant Optimizations (See PER_TENANT_OPTIMIZATION.md)**
1. Phase 1: Low-risk quick wins (30-50MB per tenant)
2. Phase 2: Gem audit and removal (30-60MB per tenant)
3. Phase 3: Advanced optimizations (70-140MB per tenant)
4. **Total: 100-150MB per tenant savings (multiplies!)**

**Future: Advanced Baseline (If Needed)**
1. Aggressive jemalloc tuning (10-30MB baseline)

### Priority Order by Impact

1. **Action Cable on-demand** - IMMEDIATE IMPACT (138MB or 36-61MB baseline)
2. **Per-tenant Rails optimizations** - HIGHEST IMPACT (multiplies by tenant count!)
3. **Advanced optimizations** - Only if quick wins insufficient

---

## Expected Results

### Conservative Estimate (Action Cable disabled + Per-tenant Phase 1+2)

**Baseline**: 169MB → 31MB (82% reduction, 138MB saved via Action Cable disabled)

**Per-tenant**: 300MB → 200MB (33% reduction, 100MB saved per tenant)
- Thread reduction: -25MB
- Connection pool optimization: -10MB
- Log level reduction: -5MB
- Gem removal: -60MB

**10 tenants total**: 169MB + 3,000MB = 3,169MB → 31MB + 2,000MB = 2,031MB (36% reduction, 1,138MB saved)

### Aggressive Estimate (Action Cable enabled+optimized + Per-tenant all phases)

**Baseline**: 169MB → 108MB (36% reduction, 61MB saved via Action Cable optimizations)
- Action Cable optimized: -50MB
- Redis tuning: -11MB

**Per-tenant**: 300MB → 150MB (50% reduction, 150MB saved per tenant)
- Phase 1+2: -100MB
- Rails component optimization: -30MB
- Eager loading disabled: -20MB

**10 tenants total**: 169MB + 3,000MB = 3,169MB → 108MB + 1,500MB = 1,608MB (49% reduction, 1,561MB saved)

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

### Action Cable Optimization Complete When:
- [ ] Action Cable optional (ENV var control working)
- [ ] Baseline memory < 35MB when disabled
- [ ] Baseline memory < 110MB when enabled + optimized
- [ ] All WebSocket channels tested
- [ ] Production stable for 1 week

### Per-Tenant Optimization Complete When:
- [ ] Per-tenant memory < 200MB (conservative target)
- [ ] All tests passing
- [ ] All features tested
- [ ] Production smoke test successful
- [ ] 10-tenant scenario measured

### Stretch Goal Complete When:
- [ ] Baseline memory < 110MB (Action Cable enabled)
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
- **Completed optimizations**: 39MB baseline + 7.1s cold start improvement + Action Cable made optional
- **See separate plans**: ACTION_CABLE_ON_DEMAND.md, PER_TENANT_OPTIMIZATION.md

---

## References

- Ruby memory profiling: https://github.com/tmm1/stackprof
- Rails memory optimization: https://www.speedshop.co/2017/12/04/malloc-doubles-ruby-memory.html
- jemalloc tuning: https://github.com/jemalloc/jemalloc/wiki/Getting-Started
- Navigator documentation: navigator/docs/
