# Kamal Migration Plan: Converge to Dockerfile.nav with Navigator

## Goals
- Single Dockerfile for both Fly.io and Kamal deployments
- Both platforms use refactored navigator (no legacy support)
- Minimal conditional logic based on environment detection
- Ensure proper file permissions for tenant processes running as `rails` user

## UID/GID Alignment ✅ VERIFIED

**Host (Kamal):**
- Files owned by `uid=1000(rubys)` and `gid=1000(rubys)`

**Container:**
- `rails` user: `uid=1000(rails) gid=1000(rails)` ✅ CONFIRMED

**Result:** Bind-mounted files owned by `rubys` (1000) on host are accessible to `rails` user (1000) in container. No permission issues.

---

## Phase 1: Get Kamal Working with Navigator

### Step 1: Update `script/nav_startup.rb`

**Add environment detection helpers at the top:**
```ruby
# Environment detection
def fly_io?
  ENV['FLY_APP_NAME']
end

def kamal?
  ENV['KAMAL_CONTAINER_NAME'] && !fly_io?
end
```

**Remove legacy navigator support:**
- Remove `--legacy` and `--refactored` argument parsing (lines 9-16)
- Remove `navigator_type` variable
- Remove the conditional rake task logic (line 83)
- Always use: `system "bin/rails nav:config"`

**Make AWS credentials optional (Fly.io only):**
```ruby
# Before (lines 34-44):
require 'bundler/setup'
require 'aws-sdk-s3'
# ...
required_env = ["AWS_SECRET_ACCESS_KEY", "AWS_ACCESS_KEY_ID", "AWS_ENDPOINT_URL_S3"]
missing_env = required_env.select { |var| ENV[var].nil? || ENV[var].empty? }

if !missing_env.empty?
  puts "Error: Missing required environment variables:"
  missing_env.each { |var| puts "  - #{var}" }
  exit 1
end

# After:
require 'bundler/setup'
require 'fileutils'
# ...
# Check for required environment variables (Fly.io only)
if fly_io?
  require 'aws-sdk-s3'

  required_env = ["AWS_SECRET_ACCESS_KEY", "AWS_ACCESS_KEY_ID", "AWS_ENDPOINT_URL_S3"]
  missing_env = required_env.select { |var| ENV[var].nil? || ENV[var].empty? }

  if !missing_env.empty?
    puts "Error: Missing required environment variables:"
    missing_env.each { |var| puts "  - #{var}" }
    exit 1
  end
end
```

**Skip ownership fixes on Kamal:**

Wrap all `chown` commands in `if fly_io?`:
- Line 57: `system "chown rails:rails #{dbpath}"` → wrap in `if fly_io?`
- Lines 64-70: ownership fix for log_volume → wrap in `if fly_io?`
- Lines 86-89: demo setup chown → wrap in `if fly_io?`
- Lines 95-101: inventory.json ownership fix → wrap in `if fly_io?`

**Skip Fly.io-specific features on Kamal:**
- Line 74: S3 sync → wrap in `if fly_io?`
- Lines 86-89: Demo setup → wrap in `if fly_io?` (will be removed in Phase 3)

### Step 2: Update `app/controllers/concerns/configurator.rb`

**Line 360 - Enable user/group isolation for Kamal:**

```ruby
# Before:
if ENV['FLY_REGION']
  config['default_memory_limit'] = '768M'
  config['user'] = 'rails'
  config['group'] = 'rails'
end

# After:
if ENV['FLY_REGION'] || ENV['KAMAL_CONTAINER_NAME']
  config['default_memory_limit'] = '768M'
  config['user'] = 'rails'
  config['group'] = 'rails'
end
```

This ensures tenant Rails processes run as the `rails` user on both platforms.

### Step 3: Copy `Dockerfile.nav` → `Dockerfile`

```bash
cp Dockerfile.nav Dockerfile
```

### Step 4: Simplify new `Dockerfile`

**Remove legacy navigator support:**

Find and remove line 53:
```dockerfile
ARG NAVIGATOR=refactored
```

Change line 68 from:
```dockerfile
    go build -ldflags="-X 'main.buildTime=${NAV_BUILD_TIME}'" \
        -o /usr/local/bin/navigator cmd/navigator-${NAVIGATOR}/main.go
```

To:
```dockerfile
    go build -ldflags="-X 'main.buildTime=${NAV_BUILD_TIME}'" \
        -o /usr/local/bin/navigator cmd/navigator-refactored/main.go
```

Change line 115 from:
```dockerfile
CMD [ "/rails/script/nav_startup.rb", "--${NAVIGATOR}" ]
```

To:
```dockerfile
CMD ["/rails/script/nav_startup.rb"]
```

**Keep demo database prep commented out for now** (line 101):
```dockerfile
# RUN SECRET_KEY_BASE=DUMMY RAILS_APP_DB=demo bin/rails db:prepare
```

### Step 5: Update `config/deploy.yml`

**Remove AWS credentials, add KAMAL_CONTAINER_NAME if needed:**

```yaml
env:
  clear:
    # Add this if Kamal doesn't auto-set it:
    # KAMAL_CONTAINER_NAME: showcase-web
  secret:
    - RAILS_MASTER_KEY
    # REMOVED: All AWS_* secrets (not needed for Kamal)
```

**Note:** Check if Kamal auto-sets `KAMAL_CONTAINER_NAME`. If it does, you don't need to add it.

### Step 6: Test Kamal Deployment

```bash
kamal deploy
```

**Verify:**
1. Deployment succeeds
2. Tenant processes run as `rails` user
3. Files are accessible (UID 1000 alignment working)
4. Navigator is serving requests

**Troubleshooting commands:**
```bash
# Check rails user UID
kamal app exec "id rails"
# Should show: uid=1000(rails) gid=1000(rails)

# Check file ownership
kamal app exec "ls -ln /data/db"
# Should show files owned by 1000:1000

# Check navigator config
kamal app exec "cat /rails/config/navigator.yml | grep -A3 pools"
# Should show user: rails, group: rails

# Check logs
kamal app logs
```

---

## Phase 2: Converge Fly.io

### Step 7: Update `fly.toml`

Change line 8 from:
```toml
  dockerfile = "Dockerfile.nav"
```

To:
```toml
  dockerfile = "Dockerfile"
```

### Step 8: Test Fly.io Deployment

```bash
fly deploy
```

**Verify:**
1. Deployment succeeds
2. No regressions in functionality
3. Both platforms now using same Dockerfile

---

## Phase 3: Move Demo Setup to Build Time

### Step 9: Uncomment demo prep in `Dockerfile`

Change line 101 from:
```dockerfile
# RUN SECRET_KEY_BASE=DUMMY RAILS_APP_DB=demo bin/rails db:prepare
```

To:
```dockerfile
RUN SECRET_KEY_BASE=DUMMY RAILS_APP_DB=demo bin/rails db:prepare
```

### Step 10: Remove demo setup from `script/nav_startup.rb`

Remove lines 86-89:
```ruby
# DELETE THESE LINES:
FileUtils.mkdir_p "/demo/db"
FileUtils.mkdir_p "/demo/storage/demo"
system "chown rails:rails /demo /demo/db /demo/storage/demo"
```

### Step 11: Test Both Deployments

```bash
# Test Kamal
kamal deploy

# Test Fly.io
fly deploy
```

**Verify:** Demo database works on both platforms

---

## Phase 4: Final Cleanup

### Step 12: Delete Obsolete Files

```bash
rm Dockerfile.nav
rm Procfile.kamal
rm bin/docker-entrypoint
```

Commit the changes:
```bash
git add -A
git commit -m "Converge Kamal and Fly.io to unified Dockerfile with navigator"
```

---

## Summary of Changes

### Files Modified
- ✏️ `script/nav_startup.rb` - Add Kamal support, remove legacy navigator
- ✏️ `app/controllers/concerns/configurator.rb` - Enable rails user for Kamal
- ✏️ `Dockerfile` - Replace with simplified Dockerfile.nav
- ✏️ `config/deploy.yml` - Remove AWS credentials
- ✏️ `fly.toml` - Point to unified Dockerfile

### Files Deleted
- 🗑️ `Dockerfile.nav`
- 🗑️ `Procfile.kamal`
- 🗑️ `bin/docker-entrypoint`

### Environment Detection Logic

| Feature | Fly.io | Kamal | Notes |
|---------|--------|-------|-------|
| Tenant user/group | ✅ rails:rails | ✅ rails:rails | Updated in configurator.rb |
| AWS S3 sync | ✅ | ❌ | Fly.io only |
| `chown` commands | ✅ | ❌ | Kamal: UID 1000 alignment makes unnecessary |
| Demo setup (runtime) | ✅ | ❌ | Phase 1-2 |
| Demo setup (build time) | ✅ | ✅ | Phase 3+ |
| Prerender | ✅ | ✅ | Both |
| Navigator config | ✅ | ✅ | Both |
| HtpasswdUpdater | ✅ | ✅ | Both |

---

## Benefits

✅ Single source of truth for both deployments
✅ Both platforms use the same navigator (refactored)
✅ Clean conditional logic (`if fly_io?` vs `if kamal?`)
✅ Proper user isolation (tenant processes run as `rails` user)
✅ UID alignment on Kamal (1000=1000) avoids permission issues
✅ Demo setup at build time (faster startup, simpler runtime)
✅ Easier maintenance going forward
✅ Reduced image size (removed nginx, passenger, ssh, rsync, rclone from Kamal)

---

## Rollback Plan

If issues occur during Phase 1:
```bash
# Revert changes to nav_startup.rb and configurator.rb
git checkout script/nav_startup.rb app/controllers/concerns/configurator.rb

# Keep old Dockerfile for Kamal
git checkout Dockerfile
```

If issues occur during Phase 2:
```bash
# Revert fly.toml
git checkout fly.toml

# Keep Dockerfile.nav for Fly.io
fly deploy
```
