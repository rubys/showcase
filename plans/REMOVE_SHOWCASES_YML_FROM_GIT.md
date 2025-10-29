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

**Status:** ⏳ Not started

### Phase 2: Migrate Application Code to db/showcases.yml

**Goal:** Stop reading from `config/tenant/showcases.yml` in application code

**Create helper method:**
```ruby
# lib/showcases_loader.rb
module ShowcasesLoader
  def self.load
    # Always read from db/showcases.yml (generated from current DB state)
    YAML.load_file(Rails.root.join('db/showcases.yml'))
  rescue Errno::ENOENT
    # Fallback for tests or initial setup
    {}
  end
end
```

**Update each file to use helper:**

1. Event.rb - Replace `YAML.load_file("#{__dir__}/../../config/tenant/showcases.yml")` with `ShowcasesLoader.load`
2. User.rb - Same replacement
3. ApplicationController - Same replacement
4. UsersController - Same replacement
5. EventController - Same replacement
6. Configurator - Update `showcases` method to use helper
7. ShowcaseInventory - Same replacement
8. LegacyConfigurator - Same replacement
9. bin/apply-changes.rb - Copy to `db/deployed-showcases.yml` instead of `config/tenant/showcases.yml`
10. script/orphan_databases.rb - Same replacement
11. script/sync_databases_s3.rb - Same replacement
12. config/environments/development.rb - Same replacement
13. Test files - Same replacement
14. db/seeds/generic.rb - Same replacement

**Status:** ⏳ Not started (blocked by Phase 1)

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

## References

- Related: `plans/KAMAL_MIGRATION_PLAN.md` (nginx dependency blocker)
- Related: `plans/AUTOMATED_SHOWCASE_REQUESTS.md` (depends on this for accurate change detection)
