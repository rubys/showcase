# Remove config/tenant/showcases.yml from Git

## Status: 📋 Planning

## Overview

Currently `config/tenant/showcases.yml` is git-tracked and used to determine deployed state. This creates a problem: admins creating showcases need to either commit the file or do a full deployment to update it. We want to move to a model where:

1. `db/showcases.yml` is generated from `db/index.sqlite3` (current DB state)
2. `db/deployed-showcases.yml` tracks what's actually deployed (not in git)
3. `config/tenant/showcases.yml` is removed from git once all dependencies are migrated

## Problem Statement

When an admin creates a showcase:
- `db/index.sqlite3` is updated
- `db/showcases.yml` is regenerated
- "Update Configuration" syncs to production machines
- **BUT** `config/tenant/showcases.yml` is unchanged
- `/admin/apply` still shows changes as "pending" because it compares to `config/tenant/showcases.yml`

## Dependencies on config/tenant/showcases.yml

### Critical Dependencies (Must migrate before removal)

1. **nginx-config.rb** (line 31)
   - `showcases = YAML.load_file("#{__dir__}/showcases.yml")`
   - Generates nginx server blocks for each showcase
   - **Blocker until Kamal migration complete** (see `plans/KAMAL_MIGRATION_PLAN.md`)

### Application Code Dependencies (Can migrate now)

2. **Event.rb** (app/models/event.rb)
   - Used to determine database file name from token
   - Can read from `db/showcases.yml` instead

3. **User.rb** (app/models/user.rb)
   - Used in `load_studios` to list available studios
   - Can read from `db/showcases.yml` instead

4. **ApplicationController** (app/controllers/application_controller.rb)
   - Used in tenant determination logic
   - Can read from `db/showcases.yml` instead

5. **UsersController** (app/controllers/users_controller.rb)
   - Used in `load_studios` for user authorization
   - Can read from `db/showcases.yml` instead

6. **EventController** (app/controllers/event_controller.rb)
   - Multiple uses for showcase listing and tenant routing
   - Can read from `db/showcases.yml` instead

7. **AdminController** (app/controllers/admin_controller.rb)
   - Used in `apply` action to compare deployed vs current state
   - **This is the key change** - use `db/deployed-showcases.yml` instead

8. **Configurator concern** (app/controllers/concerns/configurator.rb)
   - `showcases` method caches showcases.yml
   - Can read from `db/showcases.yml` instead

9. **ShowcaseInventory concern** (app/controllers/concerns/showcase_inventory.rb)
   - Used to build inventory of all showcases
   - Can read from `db/showcases.yml` instead

10. **LegacyConfigurator concern** (app/controllers/concerns/legacy_configurator.rb)
    - Multiple uses for navigator config generation
    - Can read from `db/showcases.yml` instead

### Script Dependencies (Can migrate now)

11. **bin/apply-changes.rb**
    - Copies `db/showcases.yml` → `config/tenant/showcases.yml`
    - Can be updated to copy to `db/deployed-showcases.yml` instead

12. **script/orphan_databases.rb**
    - Finds databases not in showcases.yml
    - Can read from `db/showcases.yml` instead

13. **script/sync_databases_s3.rb**
    - Uses showcases.yml to determine which databases to sync
    - Can read from `db/showcases.yml` instead

14. **script/nav_initialization.rb**
    - Generates showcases.yml on startup
    - Already generates `db/showcases.yml`, no change needed

### Development/Test Dependencies (Can migrate now)

15. **config/environments/development.rb**
    - Used to set database for development
    - Can read from `db/showcases.yml` instead

16. **Test files**
    - test/tasks/prerender_test.rb
    - test/integration/prerender_configuration_sync_test.rb
    - test/controllers/event_controller_test.rb
    - Can read from `db/showcases.yml` instead

17. **db/seeds/generic.rb**
    - Used to populate event name/date from showcases
    - Can read from `db/showcases.yml` instead

## Migration Plan

### Phase 1: Add db/deployed-showcases.yml Tracking + Helper

**Goal:** Track deployed state separately from git-tracked file, and provide safe helper for reading showcases

**Steps:**

1. **Add to .gitignore**
   ```
   db/deployed-showcases.yml
   ```

2. **Create ShowcasesLoader helper** (lib/showcases_loader.rb)
   ```ruby
   module ShowcasesLoader
     # Load showcases from the appropriate location based on environment
     # Admin machine: db/showcases.yml
     # Production: /data/db/showcases.yml (via RAILS_DB_VOLUME)
     def self.load
       dbpath = ENV['RAILS_DB_VOLUME'] || Rails.root.join('db').to_s
       file = File.join(dbpath, 'showcases.yml')
       YAML.load_file(file)
     rescue Errno::ENOENT
       # Fallback to git-tracked file during migration
       fallback_file = Rails.root.join('config/tenant/showcases.yml')
       if File.exist?(fallback_file)
         YAML.load_file(fallback_file)
       else
         # For tests or initial setup
         {}
       end
     end

     # Load deployed state for comparison (admin machine only)
     def self.load_deployed
       file = Rails.root.join('db/deployed-showcases.yml')
       YAML.load_file(file)
     rescue Errno::ENOENT
       # Fallback to git-tracked file if no deployed snapshot exists yet
       YAML.load_file(Rails.root.join('config/tenant/showcases.yml'))
     end
   end
   ```

3. **Update ConfigUpdateJob** (app/jobs/config_update_job.rb)
   ```ruby
   def perform(user_id = nil)
     # ... existing code ...

     if status.success?
       # Copy current state to deployed state after successful update
       dbpath = ENV['RAILS_DB_VOLUME'] || Rails.root.join('db').to_s
       current_file = File.join(dbpath, 'showcases.yml')
       deployed_file = Rails.root.join('db/deployed-showcases.yml')
       FileUtils.cp(current_file, deployed_file) if File.exist?(current_file)

       Rails.logger.info "ConfigUpdateJob: Updated deployed state snapshot"
       broadcast(user_id, database, 'completed', 100, 'Configuration update complete!')
     end
   end
   ```

4. **Update admin#apply** (app/controllers/admin_controller.rb)
   ```ruby
   def apply
     generate_showcases

     # Determine deployed state with fallback for migration
     deployed_file = if File.exist?('db/deployed-showcases.yml')
       'db/deployed-showcases.yml'
     else
       'config/tenant/showcases.yml'
     end

     # Use helper methods for safe loading
     before = ShowcasesLoader.load_deployed.values.reduce {|a, b| a.merge(b)}
     after = ShowcasesLoader.load.values.reduce {|a, b| a.merge(b)}

     # Detect drift between deployed snapshot and git-tracked file
     if File.exist?('db/deployed-showcases.yml')
       git_showcases = YAML.load_file('config/tenant/showcases.yml').values.reduce {|a, b| a.merge(b)}
       @showcases_drift = (before != git_showcases)
     end

     # ... rest of existing comparison logic ...
   end
   ```

4. **Update apply view** (app/views/admin/apply.html.erb)
   ```erb
   <% if @showcases_drift %>
   <h2 class="font-bold text-2xl mt-4 mb-2 text-orange-600">⚠️ Git Drift Detected</h2>
   <p class="text-sm text-gray-600 mb-2">
     config/tenant/showcases.yml is out of sync with deployed state.
     Full deployment recommended to update git-tracked file.
   </p>
   <% changes = true %>
   <% end %>
   ```

5. **Bootstrap deployed state**
   - For existing installations, initially copy current deployed state:
   ```ruby
   # Run once during deployment
   unless File.exist?('db/deployed-showcases.yml')
     FileUtils.cp('config/tenant/showcases.yml', 'db/deployed-showcases.yml')
   end
   ```

**Status:** ✅ Complete

### Phase 2: Migrate Application Code to Use ShowcasesLoader

**Goal:** Stop reading from `config/tenant/showcases.yml` directly in application code

**Completed Changes:**

All application code now uses `ShowcasesLoader.load` instead of directly reading `config/tenant/showcases.yml`:

1. ✅ Event.rb (app/models/event.rb:22)
2. ✅ User.rb (app/models/user.rb:69)
3. ✅ ApplicationController (app/controllers/application_controller.rb:82)
4. ✅ UsersController (app/controllers/users_controller.rb:260)
5. ✅ EventController (app/controllers/event_controller.rb:496, 596, 613, 1225)
6. ✅ Configurator (app/controllers/concerns/configurator.rb:35)
7. ✅ ShowcaseInventory (app/controllers/concerns/showcase_inventory.rb:10)
8. ✅ LegacyConfigurator (app/controllers/concerns/legacy_configurator.rb:224, 274, 351, 524)
9. ✅ bin/apply-changes.rb - Now copies to both `db/deployed-showcases.yml` (for change detection) and `config/tenant/showcases.yml` (git-tracked, will be removed in Phase 3)
10. ✅ script/orphan_databases.rb (script/orphan_databases.rb:35)
11. ✅ script/sync_databases_s3.rb (script/sync_databases_s3.rb:119)
12. ✅ config/environments/development.rb (config/environments/development.rb:87)
13. ✅ test/integration/prerender_configuration_sync_test.rb (line 16)
14. ✅ test/tasks/prerender_test.rb (lines 11, 48)
15. ✅ db/seeds/generic.rb (db/seeds/generic.rb:33)

**Test Results:**
- All tests pass: 1029 runs, 4782 assertions, 0 failures, 0 errors
- Code coverage: 49.67% (5518/11110)

**Status:** ✅ Complete

### Phase 3: Remove config/tenant/showcases.yml from Git

**Goal:** Delete the git-tracked file once all dependencies migrated

**Prerequisites:**
- ✅ Phase 1 complete (deployed state tracking working)
- ✅ Phase 2 complete (all application code migrated)
- ✅ Kamal migration complete (nginx no longer needs it)

**Steps:**

1. **Verify no remaining dependencies**
   ```bash
   grep -r "config/tenant/showcases.yml" app/ lib/ script/ config/
   # Should only show nginx-config.rb (if Kamal not done) or nothing
   ```

2. **Remove from git**
   ```bash
   git rm config/tenant/showcases.yml
   git commit -m "Remove showcases.yml from git - now generated from DB"
   ```

3. **Update documentation**
   - Update CLAUDE.md to explain new approach
   - Update deployment docs
   - Note that `db/showcases.yml` is now the source of truth

4. **Clean up fallback code**
   - Remove fallback to `config/tenant/showcases.yml` in admin#apply
   - Remove bootstrap code that copies from config/tenant
   - Assume `db/deployed-showcases.yml` always exists

**Status:** ⏳ Not started (blocked by Phases 1, 2, and Kamal migration)

## Benefits After Migration

1. **No git commits needed** - Admin can create showcases without git changes
2. **Clearer separation** - DB is source of truth, not git-tracked YAML
3. **Accurate change detection** - Compare current vs deployed state correctly
4. **Simpler workflow** - "Update Configuration" just works, no git drift
5. **Less confusion** - One source of truth (DB), not two (DB + git file)

## Rollback Plan

If issues arise after Phase 1:
- `db/deployed-showcases.yml` is git-ignored, can be deleted
- Code falls back to `config/tenant/showcases.yml` automatically
- No data loss, original behavior restored

## Timeline

- **Phase 1:** 2-3 hours (deploy tracking, update apply logic)
- **Phase 2:** 3-4 hours (migrate all references, test thoroughly)
- **Phase 3:** 1 hour (after Kamal migration complete)

**Total:** 6-8 hours + waiting for Kamal migration

## Possible Follow-On: Direct Database Access vs YAML Cache

### Current Architecture (Post Phase 2)

**Application Code Flow:**
1. `index.sqlite3` is the source of truth
2. `RegionConfiguration.generate_showcases_data` reads from `index.sqlite3` and generates showcases hash
3. Result is written to `/data/db/showcases.yml` (production) or `db/showcases.yml` (dev)
4. Application code calls `ShowcasesLoader.load` which reads the YAML file

**YAML Regeneration Points:**
- Production machines: `script/nav_initialization.rb` (on startup/resume) and CGI endpoint `/update_config`
- Admin machine: `generate_showcases` (called before deployments and after index.sqlite3 changes)
- Navigator: Needs YAML file for config generation (not Ruby code)

### Alternative Approach: Direct Database Access

Replace `ShowcasesLoader.load` with direct calls to `RegionConfiguration.generate_showcases_data` in application code.

**Advantages:**
1. **Always fresh data** - No cache invalidation concerns, always reads latest from index.sqlite3
2. **Simpler architecture** - Eliminate intermediate YAML file from application code path
3. **No staleness risk** - If admin modifies index.sqlite3 without calling `generate_showcases`, data is still current
4. **Fewer moving parts** - One less file to track and maintain
5. **Easier reasoning** - Direct path from database to application

**Disadvantages:**
1. **Performance** - Database query vs file read on every request (likely negligible given caching at model level)
2. **Navigator still needs YAML** - Can't eliminate the file entirely since Navigator config generation requires it
3. **Different paths on different machines** - Production uses YAML (Navigator), app code uses DB (creates asymmetry)
4. **Caching complexity** - Would need to implement caching in `RegionConfiguration` or at call sites
5. **Database locking** - More concurrent SQLite reads (though index.sqlite3 is read-mostly)

### Hybrid Approach: Cache at Model Level

Keep YAML file for Navigator, but have `RegionConfiguration.generate_showcases_data` cache its result in memory with TTL or invalidation.

**Advantages:**
- Best of both worlds: fresh data with good performance
- Single code path for all callers
- Still maintains YAML for Navigator

**Disadvantages:**
- Caching complexity (TTL, invalidation strategy)
- Memory usage for cached data structure
- Still need to track when to invalidate

### Current Status

**Decision:** Keep current approach for now (ShowcasesLoader.load reading YAML cache)

**Rationale:**
- Phases 1 & 2 are complete and working well
- No identified problems with current approach
- Performance is acceptable
- YAML file is needed for Navigator anyway

**Future Consideration:**
This change could be made incrementally (one file at a time), wholesale (all at once), or not at all depending on operational experience. Monitor for:
- Stale data issues
- Performance bottlenecks
- Cache invalidation bugs
- Complexity in understanding data flow

If problems arise, revisit this decision.

## References

- Related: `plans/KAMAL_MIGRATION_PLAN.md` (nginx dependency blocker)
- Related: `plans/AUTOMATED_SHOWCASE_REQUESTS.md` (depends on this for accurate change detection)
