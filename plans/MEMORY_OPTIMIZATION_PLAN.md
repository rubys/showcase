# Memory Optimization Plan for Navigator Multi-Tenant Deployment

## Current State
- **Baseline memory (0 tenants)**: ~350MB on Debian
- **Per-tenant memory**: ~250-350MB per Rails process (estimated)
- **Architecture**: Navigator spawns one Rails process per active tenant
- **Current optimizations**: jemalloc enabled via `LD_PRELOAD`

## Goals
- Reduce baseline memory usage to ~200-250MB (30-40% reduction)
- Reduce per-tenant memory to ~150-200MB (30-50% reduction)
- Maintain application functionality and performance
- Optimize for the multi-tenant process model

## Memory Architecture Understanding

### Baseline (0 tenants) - ~350MB
1. **Navigator Go binary** - ~20-40MB
2. **Redis server** - ~10-30MB
3. **NATS server** - ~10-30MB
4. **Ruby startup script** (nav_startup.rb) - ~50-80MB (stays resident)
5. **Vector** (if enabled) - ~10-30MB
6. **System overhead** - remaining

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

### Priority 1: Redis Memory Limits (Estimated savings: 10-20MB)

**Rationale**: Redis is running in same container and may be over-allocating memory.

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

### Priority 2: Aggressive jemalloc Tuning (Estimated savings: 10-30MB)

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

### Priority 3: Disable Vector if Not Needed (Estimated savings: 10-30MB)

**Rationale**: Vector log aggregation may not be needed for all deployments.

**Investigation**:
- Check if Vector is actually being used for log aggregation
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

### Priority 4: Optimize Ruby Startup Script (Estimated savings: 20-40MB)

**Rationale**: `script/nav_startup.rb` stays resident and loads AWS SDK.

**Investigation needed**:
- Profile memory usage of nav_startup.rb
- Determine if it needs to stay resident after initialization
- Consider moving AWS operations to separate process

**Implementation** (lazy AWS loading):
```ruby
# In script/nav_startup.rb, line 4 - lazy load AWS SDK
# Instead of:
# require 'aws-sdk-s3'

# Load only when needed:
def load_aws_sdk
  require 'aws-sdk-s3'
end

# Only load if AWS operations are needed
load_aws_sdk if ENV["AWS_ACCESS_KEY_ID"].present?
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

### Conservative Estimate (Phases 1-2)
- **Baseline**: 350MB → 280MB (20% reduction)
- **Per-tenant**: 300MB → 200MB (33% reduction)
- **10 tenants**: 3,350MB → 2,280MB (32% reduction, 1GB savings)

### Aggressive Estimate (All Phases)
- **Baseline**: 350MB → 220MB (37% reduction)
- **Per-tenant**: 300MB → 150MB (50% reduction)
- **10 tenants**: 3,350MB → 1,720MB (49% reduction, 1.6GB savings)

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
