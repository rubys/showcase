# CGI-Based Configuration Update System

## Status: ✅ Complete and Production-Verified (2025-10-27)

Replaced heavyweight redeployment process (3-5 minutes) with intelligent CGI script (<30 seconds total).

## How It Works

**Update Flow:**
1. Admin clicks "Update Configuration" → syncs index.sqlite3 to S3
2. POSTs to `/showcase/update_config` on each active Fly machine (parallel)
3. Each machine: fetches index.sqlite3, regenerates configs, returns success (<5 sec)
4. Navigator detects navigator.yml changed → reloads configuration
5. Navigator runs ready hook → prerender + event database downloads (async)

**Key Components:**
- `script/update_configuration.rb` - CGI script (fast config updates)
- `script/ready.sh` - Ready hook (async optimizations)
- `admin#trigger_config_update` - Multi-machine broadcast controller
- `/showcase/update_config` - Public CGI endpoint (replaced old `index_update`)

## Completed Implementation

**Navigator Prerequisites:**
- CGI support (v0.16.0) - user switching, access control, smart reload, timeouts
- Ready hook extension (commit e3fee85) - runs on initial start AND config reloads
- CGI reload bug fix (commit 4f441cf) - CGI scripts now persist after config reload

**Core Scripts:**
- `script/update_configuration.rb` - Fetches index.sqlite3, regenerates all configs
- `script/ready.sh` - Async prerender + event database downloads
- Direct SQLite queries (no Rails boot needed) - 5-15 second startup savings

**UI & Controller:**
- `admin#apply` - Conditional UI (CGI update vs full deployment)
- `admin#trigger_config_update` - Multi-machine broadcast with streaming output
- `script/user-update` - Updated to use new CGI endpoint

**Architecture Patterns:**
- Always-regenerate strategy (simpler than change detection)
- S3 as authoritative source (--safe mode prevents stale overwrites)
- Parallel execution across machines (Fly-Force-Instance-Id targeting)
- Zero downtime (async optimizations via ready hook)

## Lessons Learned

**Performance Insights:**
- Direct SQLite queries (vs ActiveRecord) save 5-15 seconds on startup/resume
- Ready hook pattern enables fast CGI response while optimizations run async
- --safe mode prevents race conditions from suspended machines

**Architecture Decisions:**
- Always-regenerate is simpler and more reliable than change detection
- Extending ready hook (vs creating new hook type) reduced Navigator complexity
- S3 as single source of truth eliminates state divergence issues
- Intermediate files (showcases.yml) should eventually be eliminated

**Implementation Gotchas:**
- CGI script permissions needed elevation (root) for rsync operations
- Navigator CGI reload bug (4f441cf) discovered during production deployment
- showcases.yml must be regenerated whenever index.sqlite3 changes
- JSON fixture files (deployed.json, regions.json) need database fallbacks

## Remaining Work

### Index Database as Source of Truth (Post-MVP)

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

### Deprecate Old Routes

1. Keep `event#index_update` for backward compatibility
2. Document new workflow
3. Add deprecation notice to old route
4. Remove after transition period

## Future Enhancements

1. **Change Preview & Dry Run**
   - Show what will change before executing
   - Require confirmation for destructive changes

2. **Operation History & Audit Trail**
   - Log all configuration updates
   - Track what changed and when

3. **Webhook Support**
   - Trigger updates via webhook (GitHub, CI/CD)
   - Automatic updates on index database changes

4. **Admin Server Map Generation and S3 Upload**
   - **Problem:** map.yml needs makemaps.js (node) to add projection coordinates
   - **Current limitation:** Node not available in production containers
   - **Proposed solution:** Admin server generates map.yml with projections, uploads to S3
   - **Benefits:** Production containers stay lightweight, map updates without Docker rebuild

## References

- [Navigator CGI Documentation](https://rubys.github.io/navigator/features/cgi-scripts/)
- Navigator commits: [e3fee85](https://github.com/rubys/navigator/commit/e3fee85) (ready hook), [4f441cf](https://github.com/rubys/navigator/commit/4f441cf) (CGI reload fix)
- Key files: `script/update_configuration.rb`, `script/ready.sh`, `app/controllers/concerns/configurator.rb`