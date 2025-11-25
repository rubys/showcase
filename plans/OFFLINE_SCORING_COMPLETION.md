# Offline Scoring Completion Plan

## Overview

This plan documents the remaining steps to complete the offline-first scoring feature for judges during live dance competition events. The core architecture is complete:

- **ERB-to-JS converter**: Working (232 + 831 lines)
- **Heat hydrator**: Working (380 lines)
- **Templates controller**: Working (101 lines)
- **Stimulus controller**: Working (270 lines)
- **Dirty scores queue**: Working (276 lines)
- **Service worker**: Working (65 lines)

What remains is integration, polish, and production validation.

## Current State

### Complete

1. **Template Conversion Pipeline**
   - `ErbPrismConverter` parses ERB → Prism AST → JavaScript functions
   - `/templates/scoring.js` serves converted templates as ES modules
   - All 4 heat types convert successfully (solo, rank, table, cards)
   - 42 converter tests passing

2. **Data Serialization**
   - `heats_data` endpoint returns normalized JSON (~176KB for 1,362 heats)
   - Server computes derived values (dance_string, subject_lvlcat, etc.)
   - Category scoring expansion for amateur couples

3. **Client-Side Hydration**
   - `buildLookupTables()` creates O(1) lookup maps
   - `hydrateHeat()` converts IDs to nested objects
   - `buildHeatTemplateData()` prepares complete template data

4. **Heat Rendering**
   - `heat_app_controller.js` loads templates and data
   - Heat navigation without server round-trips
   - Template selection based on heat properties

5. **Offline Infrastructure**
   - `DirtyScoresQueue` in IndexedDB
   - Service worker with network-first caching
   - Version check endpoint for smart refresh

### Incomplete / In Progress

1. **Score Posting Integration**
   - Current: Scores POST to server, no offline fallback
   - Needed: Queue scores in DirtyScoresQueue when offline

2. **Offline UI Indicators**
   - Current: No visual indication of offline state
   - Needed: Connection status indicator, pending scores badge

3. **Batch Upload on Reconnection**
   - Current: Manual upload only
   - Needed: Automatic batch upload when connectivity returns

4. **Navigation Guard**
   - Current: Can navigate away and lose SPA state while offline
   - Needed: Warn before leaving SPA when offline

5. **Heat List Rendering**
   - Current: `showHeatList()` has placeholder
   - Needed: Full heat list with navigation

6. **Production Validation**
   - Needed: Test at actual live event

## Implementation Steps

### Phase 1: Score Posting with Offline Queue

**Files to modify:**
- `app/javascript/controllers/heat_app_controller.js`
- `app/javascript/helpers/heat_data_manager.js`

**Tasks:**

1. **Wire up score POST handling**
   ```javascript
   // In heat_app_controller.js
   async handleScoreSubmit(event) {
     const scoreData = this.extractScoreData(event.target);

     try {
       await this.postScore(scoreData);
       this.updateInMemoryScore(scoreData);
     } catch (error) {
       // Queue for later
       await this.dirtyScoresQueue.add(scoreData);
       this.updateInMemoryScore(scoreData);
       this.updatePendingIndicator();
     }
   }
   ```

2. **Integrate DirtyScoresQueue**
   - Import queue in controller
   - Initialize on connect
   - Add to queue on POST failure
   - Clear from queue on POST success

3. **Add pending scores tracking**
   - Track count of pending scores
   - Expose count for UI display

**Estimated effort:** 2-3 hours

### Phase 2: Automatic Batch Upload

**Files to modify:**
- `app/javascript/controllers/heat_app_controller.js`
- `app/javascript/helpers/connectivity_tracker.js`

**Tasks:**

1. **Set up connectivity listeners**
   ```javascript
   window.addEventListener('online', () => this.handleOnline());
   window.addEventListener('offline', () => this.handleOffline());
   ```

2. **Implement batch upload flow**
   ```javascript
   async handleOnline() {
     const pending = await this.dirtyScoresQueue.getAll();
     if (pending.length === 0) return;

     try {
       const response = await fetch(`/scores/${this.judgeId}/batch`, {
         method: 'POST',
         headers: { 'Content-Type': 'application/json' },
         body: JSON.stringify({ scores: pending })
       });

       if (response.ok) {
         await this.dirtyScoresQueue.clear();
         await this.refreshData();
         this.updatePendingIndicator();
       }
     } catch (error) {
       // Will retry on next connectivity change
       console.log('[HeatApp] Batch upload failed, will retry');
     }
   }
   ```

3. **Refresh data after batch upload**
   - Fetch fresh data from heats_data endpoint
   - Rebuild lookup tables
   - Re-render current heat

**Estimated effort:** 2-3 hours

### Phase 3: Offline UI Indicators

**Files to create/modify:**
- `app/javascript/components/connection_status.js` (new)
- `app/views/scores/spa.html.erb`
- `app/assets/stylesheets/connection_status.css` (new)

**Tasks:**

1. **Create connection status component**
   - WiFi icon that changes color (green = online, red = offline)
   - Badge showing pending scores count
   - Positioned in corner of scoring interface

2. **Add to SPA view**
   ```erb
   <div data-controller="connection-status">
     <div data-connection-status-target="indicator"></div>
     <div data-connection-status-target="pending"></div>
   </div>
   ```

3. **Style connection status**
   - Clear visual distinction between online/offline
   - Non-intrusive but visible
   - Touch-friendly for tablet use

**Estimated effort:** 2 hours

### Phase 4: Navigation Guard

**Files to modify:**
- `app/javascript/controllers/heat_app_controller.js`

**Tasks:**

1. **Intercept navigation when offline**
   ```javascript
   document.addEventListener('turbo:before-visit', (event) => {
     if (!navigator.onLine && !this.isSPARoute(event.detail.url)) {
       const confirmed = confirm(
         "You're offline. Leaving this page may prevent you from " +
         "returning until you're back online. Continue?"
       );
       if (!confirmed) event.preventDefault();
     }
   });
   ```

2. **Add beforeunload handler for hard navigation**
   ```javascript
   window.addEventListener('beforeunload', (event) => {
     if (!navigator.onLine && this.hasPendingScores()) {
       event.preventDefault();
       event.returnValue = '';
     }
   });
   ```

**Estimated effort:** 1 hour

### Phase 5: Heat List Rendering

**Files to modify:**
- `app/javascript/controllers/heat_app_controller.js`
- `lib/erb_prism_converter.rb` (if needed for heatlist template)

**Tasks:**

1. **Implement showHeatList()**
   - Use converted heatlist template
   - Group heats by category/ballroom
   - Show current heat indicator

2. **Add heat list navigation**
   - Click heat number to navigate
   - Previous/next heat buttons

3. **Handle fractional heat numbers**
   - Some heats have sub-numbers (e.g., 5a, 5b)
   - Navigation should handle slot progression

**Estimated effort:** 3-4 hours

### Phase 6: Testing

**Files to create:**
- `test/javascript/heat_app_controller.test.js`
- `test/system/offline_scoring_test.rb`

**Tasks:**

1. **JavaScript unit tests**
   - Score posting with offline fallback
   - Batch upload flow
   - Version comparison logic
   - Heat navigation

2. **System tests**
   - Load SPA successfully
   - Score entry works
   - Navigation between heats

3. **Manual testing scenarios**
   - Enter scores, go offline, enter more scores, go online
   - Navigate while offline
   - Batch upload verification
   - Multiple tabs handling

**Estimated effort:** 4-6 hours

### Phase 7: Production Validation

**Tasks:**

1. **Deploy to staging environment**
   - Verify with real event database
   - Test with multiple judges simultaneously

2. **Test at actual event**
   - Monitor for issues during live scoring
   - Gather feedback from judges
   - Verify scores sync correctly

3. **Post-event review**
   - Review logs for errors
   - Analyze offline queue usage
   - Document any issues found

**Estimated effort:** Depends on event schedule

## Open Questions

### 1. Duplicate DirtyScoresQueue Implementations

**Issue:** Two implementations exist:
- `app/javascript/lib/dirty_scores_queue.js` (store-per-score model)
- `app/javascript/helpers/dirty_scores_queue.js` (store-per-judge model)

**Question:** Which should be canonical?

**Recommendation:** Use the helpers version (store-per-judge) because:
- Matches existing heat_data_manager integration
- Simpler batch upload (all scores for one judge)
- Easier to manage per-judge queue state

**Action:** Remove lib version, update any imports

### 2. Two ERB Converters

**Issue:** Two converters exist:
- `ErbToJsConverter` (232 lines, regex-based)
- `ErbPrismConverter` (831 lines, AST-based)

**Question:** Should we consolidate?

**Recommendation:** Keep ErbPrismConverter as canonical:
- More robust (AST-based parsing)
- Better error handling
- Handles more Ruby patterns

**Action:** Update any references, consider removing ErbToJsConverter

### 3. Category Scoring Edge Cases

**Issue:** Category scoring expands amateur couples into separate rows. Complex logic in both heats_data and heat_hydrator.

**Question:** Is the expansion logic consistent between server and client?

**Recommendation:** Verify with test database:
- Run render_erb_and_js.rb on category scoring heats
- Compare row counts and student assignments
- Document any differences

**Action:** Add test cases for category scoring heats

### 4. CSRF Token for Batch Upload

**Issue:** Batch endpoint skips CSRF verification (protected by Basic Auth + judge URL).

**Question:** Is this acceptable for production?

**Recommendation:** Current approach is acceptable:
- Judge-specific URLs require Basic Auth
- Pre-signed URLs would need to change anyway
- Can add CSRF token refresh endpoint later if needed

**Action:** Document security model in ARCHITECTURE.md

## Success Criteria

### Must Have (MVP)

- [ ] Scores entered while offline are queued in IndexedDB
- [ ] Queued scores upload automatically when connectivity returns
- [ ] Visual indicator shows offline status
- [ ] Visual indicator shows pending scores count
- [ ] Navigation between heats works offline
- [ ] All 4 heat types render correctly (solo, rank, table, cards)
- [ ] No data loss during normal offline/online transitions

### Should Have

- [ ] Navigation guard warns before leaving SPA while offline
- [ ] Heat list shows all heats with category grouping
- [ ] Previous/next heat navigation
- [ ] Tests cover critical paths

### Nice to Have

- [ ] Smart preloading of adjacent heats
- [ ] Offline page shell via Service Worker
- [ ] Multi-tab coordination via BroadcastChannel

## Timeline

**Phase 1-4 (Core Offline Functionality):** 1-2 days
**Phase 5 (Heat List):** Half day
**Phase 6 (Testing):** 1 day
**Phase 7 (Production):** Dependent on event schedule

**Total estimated:** 3-4 days of development work

## References

- Blog: [Offline-First Scoring with Web Components](/2025/11/07/Offline-First-Web-Components.html)
- Blog: [Simpler Offline Scoring with Turbo MVC](/2025/11/20/Turbo-MVC-Offline.html)
- Blog: [Automatic ERB-to-JavaScript Conversion](/2025/11/24/ERB-to-JavaScript-Conversion.html)
- Plan: [SPA Sync Strategy](./SPA_SYNC_STRATEGY.md)
- Plan: [ERB Converter Integration Status](./ERB_CONVERTER_INTEGRATION_STATUS.md)
- Plan: [Stimulus Implementation Status](./STIMULUS_IMPLEMENTATION_STATUS.md)
