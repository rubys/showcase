# Per-Tenant Memory Optimization Plan

## Overview

**Impact**: Per-tenant optimizations multiply by active tenant count!
- 5 tenants × 100MB savings = 500MB total
- 10 tenants × 100MB savings = 1GB total

**Current per-tenant memory**: ~250-350MB per Rails process

**Goal**: Reduce to ~150-200MB per tenant (33-50% reduction)

---

## Current Per-Tenant Breakdown

Estimated memory per Rails tenant process:
1. Ruby VM - ~20-40MB
2. Rails framework - ~80-120MB
3. Application code - ~30-50MB
4. Loaded gems - ~60-100MB
5. Thread overhead (5 threads) - ~50-75MB
6. Connection pools - ~10-20MB

**Total**: ~250-350MB

---

## Priority 1: Disable Unused Rails Components (Estimated: 50-100MB per tenant)

**Current**: Loading full Rails stack with `require "rails/all"`

**Opportunity**: Selectively require only needed components

### Implementation

**File**: `config/application.rb`

**Before**:
```ruby
require "rails/all"
```

**After**:
```ruby
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

### Investigation Needed

Determine if these components are used:
- **Active Storage** - File uploads (10-20MB potential savings)
- **Action Mailer** - Email sending (10-15MB potential savings)
- **Active Job** - Background jobs (5-10MB potential savings)

**Method**: Search codebase for usage
```bash
grep -r "ActiveStorage" app/ lib/
grep -r "ActionMailer" app/ lib/
grep -r "ActiveJob" app/ lib/
```

### Risk

LOW-MEDIUM - Requires thorough testing
- Test all features after disabling components
- Verify no runtime errors from missing frameworks

### Testing

1. Run full test suite: `bin/rails test`
2. Run system tests: `bin/rails test:system`
3. Manual testing of all major features
4. Check error logs for missing constant errors

---

## Priority 2: Reduce Thread Count (Estimated: 20-30MB per tenant)

**Current**: 5 threads per tenant Rails process

**Opportunity**: Reduce to 2 threads - Navigator handles concurrency by spawning multiple processes

### Implementation

**File**: `config/puma.rb`

**Before**:
```ruby
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
```

**After**:
```ruby
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 2 }
```

**Alternative**: Set via Navigator process config in `configurator.rb`

### Trade-off

Lower per-process concurrency (mitigated by Navigator spawning multiple processes as needed)

### Risk

LOW - Navigator architecture designed for multi-process concurrency

### Testing

Load test with concurrent requests:
- 10+ concurrent users per tenant
- Verify response times acceptable
- Check Navigator spawns additional processes if needed

---

## Priority 3: Disable Eager Loading (Estimated: 20-40MB per tenant)

**Current**: `config.eager_load = true` loads all classes upfront

**Opportunity**: Use lazy loading - trades slightly slower first request for lower memory

### Implementation

**File**: `config/environments/production.rb`

**Before**:
```ruby
config.eager_load = true
```

**After**:
```ruby
config.eager_load = false
```

### Trade-off

First request to each controller ~50-100ms slower as classes load on demand

### Risk

LOW-MEDIUM
- May expose autoload issues not caught in tests
- Requires thread-safe autoloading (Rails 8 zeitwerk handles this)

### Testing

1. Test cold start performance
2. Measure first request to each controller
3. Verify no autoload errors in logs
4. Load test to ensure thread safety

---

## Priority 4: Remove Unused Gems (Estimated: 30-60MB per tenant)

**Investigation needed** - determine if these gems are used:

### Candidate Gems for Removal

1. **geocoder** (~5-10MB) - Geolocation services
   ```bash
   grep -r "Geocoder\|geocode" app/ lib/
   ```

2. **combine_pdf** (~10MB) - PDF generation
   ```bash
   grep -r "CombinePDF" app/ lib/
   ```

3. **fast_excel** (~5-10MB) - Excel export
   ```bash
   grep -r "FastExcel" app/ lib/
   ```

4. **sentry-ruby/sentry-rails** (~10MB) - Error tracking
   ```bash
   grep -r "Sentry" app/ lib/ config/
   ```
   **Note**: Worth the memory cost for production error tracking?

### Process

1. Search for gem usage in codebase
2. Check if gem is in Gemfile but never imported
3. If unused, remove from Gemfile
4. Run tests to verify no breakage
5. Deploy and monitor for errors

### Risk

LOW - Easy to revert if needed

---

## Priority 5: Reduce Log Level (Estimated: 5-10MB per tenant)

**Current**: Debug logging (verbose)

**Opportunity**: Use :info or :warn level

### Implementation

**File**: `config/environments/production.rb`

**Before**:
```ruby
config.log_level = :debug
```

**After**:
```ruby
config.log_level = :info  # or :warn
```

### Trade-off

Less detailed logs for debugging production issues

### Risk

LOW - Can temporarily change to debug when troubleshooting

---

## Priority 6: Optimize Connection Pool (Estimated: 5-10MB per tenant)

**Current**: Pool size may not match thread count

**Opportunity**: Match pool to threads

### Implementation

**File**: `config/database.yml`

**Before**:
```yaml
production:
  pool: <%= ENV.fetch("RAILS_DB_POOL") { 5 } %>
```

**After**:
```yaml
production:
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 2 } %>
```

### Risk

VERY LOW - Pool should match thread count

---

## Implementation Strategy

### Phase 1: Low-Risk Quick Wins (First Sprint)

1. Reduce thread counts (Priority 2) - 20-30MB per tenant
2. Optimize connection pool (Priority 6) - 5-10MB per tenant
3. Reduce log level (Priority 5) - 5-10MB per tenant

**Total Phase 1**: ~30-50MB per tenant savings

### Phase 2: Gem Audit (Second Sprint)

1. Audit gem usage (Priority 4)
2. Remove unused gems - 30-60MB per tenant
3. Test thoroughly after each removal

**Total Phase 2**: Additional 30-60MB per tenant savings

### Phase 3: Advanced Optimizations (If Needed)

1. Disable unused Rails components (Priority 1) - 50-100MB per tenant
2. Disable eager loading (Priority 3) - 20-40MB per tenant

**Total Phase 3**: Additional 70-140MB per tenant savings

---

## Expected Results

### Conservative Estimate (Phase 1 + Phase 2)

**Per-tenant**: 300MB → 200MB (33% reduction, 100MB saved per tenant)
- Thread reduction: -25MB
- Connection pool optimization: -10MB
- Log level reduction: -5MB
- Gem removal: -60MB

**10 tenants total**: 3,000MB → 2,000MB (33% reduction, 1GB saved)

### Aggressive Estimate (All Phases)

**Per-tenant**: 300MB → 150MB (50% reduction, 150MB saved per tenant)
- Phase 1+2: -100MB
- Rails component optimization: -60MB
- Eager loading disabled: -20MB

**10 tenants total**: 3,000MB → 1,500MB (50% reduction, 1.5GB saved)

---

## Measurement and Validation

### Measure Per-Tenant Memory

```bash
# SSH to Fly.io container
fly ssh console -a smooth-nav -C "ps auxww"

# Filter Rails tenant processes
fly ssh console -a smooth-nav -C "ps auxww" | grep "rails/config.ru"

# Calculate average per tenant
fly ssh console -a smooth-nav -C "ps auxww" | \
  grep "rails/config.ru" | \
  awk '{sum+=$6; count++} END {print "Average per tenant: " sum/count/1024 " MB (" count " tenants)"}'
```

### Track Over Time

Create a monitoring script:

```bash
#!/bin/bash
# Monitor tenant memory usage
while true; do
  echo "=== $(date) ==="
  fly ssh console -a smooth-nav -C "ps auxww" | grep "rails/config.ru" | \
    awk '{sum+=$6; count++} END {if(count>0) print count " tenants, avg " sum/count/1024 " MB each"}'
  sleep 300  # Check every 5 minutes
done
```

---

## Testing Plan

### Phase 1 Testing

1. **Local testing**:
   ```bash
   # Apply Phase 1 changes
   RAILS_MAX_THREADS=2 bin/dev

   # Run tests
   bin/rails test
   bin/rails test:system
   ```

2. **Staging deployment**:
   ```bash
   fly deploy -a smooth-nav --region iad
   ```

3. **Load testing**:
   - Spawn 5+ tenant processes
   - Concurrent requests per tenant
   - Measure memory and response times

4. **Production verification**:
   - Deploy to one region first
   - Monitor for 24 hours
   - Check error rates and performance
   - Roll out to remaining regions

### Phase 2 Testing

For each gem removal:
1. Search codebase for usage
2. Remove from Gemfile
3. Run full test suite
4. Deploy to staging
5. Manual feature testing
6. Deploy to production with monitoring

### Phase 3 Testing

More rigorous due to higher risk:
1. Full test suite (unit + system)
2. Extended staging deployment (1 week)
3. Load testing under high concurrency
4. Monitor autoload errors
5. Gradual production rollout

---

## Success Criteria

### Phase 1 Complete When:
- ✅ Per-tenant memory < 250MB
- ✅ All tests passing
- ✅ No performance degradation
- ✅ Production stable for 1 week

### Phase 2 Complete When:
- ✅ Per-tenant memory < 200MB
- ✅ All features tested after gem removal
- ✅ Production smoke test successful
- ✅ No errors from missing gems

### Phase 3 Complete When:
- ✅ Per-tenant memory < 180MB
- ✅ System stable under load
- ✅ No autoload errors
- ✅ Memory usage predictable

---

## Rollback Plan

Each optimization:
- Committed separately
- Tested independently
- Easily revertable via `git revert <commit-hash>`

**Emergency rollback**:
```bash
git revert <commit-hash>
git push
fly deploy -a smooth-nav
```

---

## Notes

- **Multi-tenant architecture**: Savings multiply by active tenant count
- **Trade-offs**: Some optimizations may slightly impact first-request performance
- **Testing critical**: Each change validated with full test suite
- **Incremental approach**: Start with low-risk wins, measure, then optimize further
- **Monitor closely**: Watch error rates and performance metrics after each phase

---

## References

- Ruby memory profiling: https://github.com/tmm1/stackprof
- Rails memory optimization: https://www.speedshop.co/2017/12/04/malloc-doubles-ruby-memory.html
- Rails component loading: https://guides.rubyonrails.org/initialization.html
- Puma thread configuration: https://github.com/puma/puma/blob/master/docs/deployment.md
