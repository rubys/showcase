# Showcase Request Redirect Options Analysis

## Context

After a studio owner creates a new showcase request and the ConfigUpdateJob completes (~30 seconds), where should they be redirected?

**Current situation:**
- Progress bar completes
- User redirected to studio list page (`/showcase/studios/:location_key`)
- **Problem**: Studio list pages are prerendered, so the new event won't appear until prerendering completes (several more seconds)
- **Bad UX**: User waits 30 seconds, gets redirected, doesn't see their new event, thinks something failed

## Production File Structure (Verified via fly ssh)

```
/rails/public/
├── studios/
│   ├── clearwater/
│   │   └── index.html        # Prerendered studio list page
│   ├── kennesaw/
│   │   └── index.html
│   └── ...
├── 2025/
│   ├── clearwater/
│   │   └── index.html        # Prerendered event list (multiple events per year)
│   ├── kennesaw/
│   │   └── index.html        # Prerendered single event (one event per year)
│   └── ...
└── regions/
    └── ...
```

**Key observations:**
1. Studio list pages: `/rails/public/studios/:location_key/index.html`
2. Event pages vary by pattern:
   - Single event/year: `/rails/public/:year/:location_key/index.html`
   - Multiple events/year: `/rails/public/:year/:location_key/:event_key/index.html`

## Update Flow

1. User creates showcase on rubix (admin machine)
2. ConfigUpdateJob runs on rubix:
   - Syncs index.sqlite3 to S3
   - Calls `/showcase/update_config` CGI endpoint on each Fly machine
3. Each machine (`script/update_configuration.rb`):
   - Fetches index.sqlite3 from S3
   - Updates htpasswd
   - Regenerates showcases.yml
   - Generates navigator config
   - Navigator detects config change → reloads
4. Navigator ready script runs (post-reload hook):
   - Prerenders pages (including updated studio list)
   - Updates event databases

**Timeline:**
- ConfigUpdateJob broadcasts "completed": ~30s
- Prerendering starts: ~30s
- Prerendering completes: +several seconds (depends on page complexity)

---

## Option 1: Redirect to New Event Page

### Approach

Redirect to the newly created event:
- Single event/year: `/showcase/:year/:location_key`
- Multiple events/year: `/showcase/:year/:location_key/:event_key`

### Implementation

**Challenge**: Determine URL pattern dynamically

```ruby
# In ShowcasesController#create (regular user path)

# Count events for this location/year to determine URL pattern
events_this_year = Showcase.where(
  location_id: @showcase.location_id,
  year: @showcase.year
).count

if events_this_year == 1
  # Single event - no event key in URL
  @return_to = "/showcase/#{@showcase.year}/#{@location_key}"
else
  # Multiple events - include event key
  @return_to = "/showcase/#{@showcase.year}/#{@location_key}/#{@showcase.key}"
end
```

### Pros

✅ **Immediate confirmation** - User sees their new event right away
✅ **No stale page issue** - Event page renders dynamically (not prerendered yet)
✅ **Clear success** - Landing on the event they just created feels right
✅ **Simple logic** - Just count events to determine URL pattern
✅ **Works immediately** - No waiting for prerendering

### Cons

❌ **URL pattern complexity** - Need to handle single vs multiple events
❌ **Edge case risk** - What if count changes between creation and redirect?
❌ **Database query** - Need to count events (though this is fast)
❌ **Not where user came from** - They started at studio list, now they're on event page

### Code Changes Required

1. Update `ShowcasesController#create` (regular user path):
   ```ruby
   # Determine redirect URL based on events count
   events_this_year = Showcase.where(
     location_id: @showcase.location_id,
     year: @showcase.year
   ).count

   @return_to = if events_this_year == 1
     "/showcase/#{@showcase.year}/#{@location_key}"
   else
     "/showcase/#{@showcase.year}/#{@location_key}/#{@showcase.key}"
   end
   ```

2. No other changes needed

**Complexity**: Low (5-10 lines of code)

---

## Option 2: Cache Invalidation

### Approach

Redirect to studio list page as originally intended, but **delete the prerendered version** so it renders dynamically with the new event until prerendering completes.

### Implementation Strategy

**Where to invalidate**: In `script/update_configuration.rb` (the CGI script that runs on each machine)

```ruby
# After Operation 3: Showcases generation
# Add Operation 3.5: Cache invalidation

log ""
log "Operation 3.5/4: Invalidating affected studio list cache"
log "-" * 70

begin
  # Determine which studio pages to invalidate by comparing old vs new showcases
  old_showcases = if File.exist?(showcases_file)
    YAML.load_file(showcases_file)
  else
    {}
  end

  # Collect affected studios (any studio with changes)
  affected_studios = Set.new

  # Compare each year's showcases
  showcases_data.each do |year, locations|
    old_year = old_showcases[year] || {}

    locations.each do |location_key, events|
      old_events = old_year[location_key] || {}

      # If events changed, mark studio as affected
      if events != old_events
        affected_studios.add(location_key)
      end
    end
  end

  # Delete prerendered studio list pages for affected studios
  affected_studios.each do |studio_key|
    cache_file = Rails.root.join('public', 'studios', studio_key, 'index.html')
    if File.exist?(cache_file)
      File.delete(cache_file)
      log "Invalidated cache for studio: #{studio_key}"
    end
  end

  log "SUCCESS: Invalidated #{affected_studios.size} studio caches"
rescue => e
  log "WARNING: Cache invalidation failed: #{e.message}"
  log "Continuing anyway (not critical)"
  # Don't fail the whole update for cache invalidation
end
```

### Pros

✅ **Simple redirect** - Just use studio list URL, no URL pattern logic
✅ **Returns to origin** - User came from studio list, returns to studio list
✅ **Shows new event** - Deleted cache means dynamic render with fresh data
✅ **Eventually consistent** - Prerendering will recreate cache file later
✅ **Surgical** - Only invalidates studios that actually changed

### Cons

❌ **More complex implementation** - Need to compare old vs new, delete files
❌ **Distributed problem** - Must invalidate on ALL machines, not just one
❌ **Timing sensitive** - What if prerender happens before invalidation?
❌ **Failure modes** - What if file deletion fails? Permission issues?
❌ **Cache location assumptions** - Assumes `/rails/public/studios/...` structure
❌ **Not atomic** - Gap between config update and cache invalidation
❌ **Comparison overhead** - YAML diff on every update

### Code Changes Required

1. Modify `script/update_configuration.rb`:
   - Save old showcases before generating new ones
   - Compare old vs new to find affected studios
   - Delete cache files for affected studios
   - Handle errors gracefully (don't fail whole update)

2. Consider edge cases:
   - What if showcases.yml doesn't exist yet?
   - What if public/studios directory doesn't exist?
   - What if deletion fails (permissions, etc.)?
   - What if multiple events affect same studio?

**Complexity**: Medium-High (30-50 lines of code + error handling)

---

## Option 3: Hybrid Approach (Alternative)

### Approach

Redirect to new event page, but also invalidate studio list cache for completeness.

### Pros

✅ All benefits of Option 1 (immediate event page)
✅ Plus: Studio list is fresh when user clicks "back to studio"

### Cons

❌ All cons of both options combined
❌ More complex than either alone

**Verdict**: Probably overkill

---

## Recommendation: Option 1 (Redirect to New Event)

### Reasoning

1. **Simpler implementation** - 5-10 lines vs 30-50 lines
2. **Fewer failure modes** - No file operations, no permissions issues
3. **Better UX** - User sees their new event immediately, clear success
4. **Self-contained** - Logic stays in Rails controller, no touching CGI scripts
5. **Faster to implement** - Can be done in single commit
6. **Easier to test** - No distributed system concerns
7. **Less risky** - Doesn't touch critical update_configuration.rb script

### Counter to Cache Invalidation Complexity

The cache invalidation approach has several hidden complexities:

1. **Timing issues**: Prerender might start before cache invalidation runs
2. **Distributed sync**: Need to invalidate on ALL machines (3-6 machines)
3. **File system operations**: Permission issues, I/O errors, race conditions
4. **Comparison logic**: What if showcases.yml format changes? What about nested events?
5. **Maintenance burden**: CGI script becomes more complex, harder to debug

### URL Pattern Edge Case Handling

The "What if count changes?" concern is minimal because:
- Count happens after save (in same request)
- No concurrent modifications (user is still watching progress bar)
- Worst case: 404 on event page, user clicks "Studios" → sees event in list
- This is rare and recoverable

### Implementation Plan for Option 1

```ruby
# In app/controllers/showcases_controller.rb, create action, regular user path:

else
  # For regular users: Show progress bar with real-time updates
  user = User.find_by(userid: @authuser)

  if user && Rails.env.production?
    ConfigUpdateJob.perform_later(user.id)
  end

  # Set variables for progress view
  @location_key = @showcase.location&.key
  @location = @showcase.location
  @show_progress = true

  # Determine redirect URL: new event page (better UX than stale studio list)
  # Count events this year to determine URL pattern
  events_this_year = Showcase.where(
    location_id: @showcase.location_id,
    year: @showcase.year
  ).count

  @return_to = if events_this_year == 1
    # Single event - URL: /showcase/:year/:location_key
    "/showcase/#{@showcase.year}/#{@location_key}"
  else
    # Multiple events - URL: /showcase/:year/:location_key/:event_key
    "/showcase/#{@showcase.year}/#{@location_key}/#{@showcase.key}"
  end

  # Render new_request view which now has progress bar
  format.html { render :new_request, status: :ok }
end
```

### Testing

```bash
# Test single event scenario
showcase = Showcase.create!(location: kennesaw, year: 2025, key: 'showcase', ...)
# Expected redirect: /showcase/2025/kennesaw

# Test multiple events scenario
showcase = Showcase.create!(location: clearwater, year: 2025, key: 'beach-ball', ...)
# Expected redirect: /showcase/2025/clearwater/beach-ball
```

---

## Conclusion

**Recommended**: Option 1 (Redirect to New Event Page)

**Rationale**: Simpler, safer, better UX, easier to maintain, fewer failure modes.

The cache invalidation approach, while elegant in theory, introduces significant complexity for marginal benefit. The user wants to see their new event - let's show it to them directly.
