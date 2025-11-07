# SPA Sync Strategy

## Goal

Implement a robust online/offline sync strategy where Rails server is always the source of truth when online, with graceful offline fallback.

## Architecture Principles

1. **Rails is Source of Truth**: When online, always prefer server data over cached data
2. **Minimal Bandwidth**: Use lightweight version checks instead of full data fetches
3. **Offline Support**: Queue score updates when offline, batch upload when reconnected
4. **No Drift**: Changes by other judges or scratched heats automatically sync

## Current State (Before This Plan)

- Initial load: Fetch all heat data from `/scores/:judge/heats.json`
- Store in IndexedDB with 1-hour staleness check (timestamp-based)
- In-memory `this.data` is source of truth after load
- Individual score POSTs go to Rails
- **Problem**: No awareness of server-side changes (scratches, heat updates)
- **Problem**: No offline queue for failed POSTs
- **Problem**: Staleness check only on page load, navigation uses stale in-memory data

## Proposed Flow

### Heat Navigation (Online)

1. User navigates to next/previous heat
2. Client calls `GET /scores/:judge/version/:heat_number`
3. Server returns lightweight version metadata:
   ```json
   {
     "max_updated_at": "2025-11-06T15:30:00Z",
     "heat_count": 142
   }
   ```
4. Client compares with cached version metadata
5. **If changed**: Fetch full data from `/scores/:judge/heats.json`, update cache
6. **If same**: Use cached data (no fetch needed)

### Heat Navigation (Offline)

1. User navigates to next/previous heat
2. Network request fails (timeout/error)
3. Use last successfully cached data from IndexedDB
4. Continue allowing score entry (queued in dirty list)

### Score Entry (Online)

1. User enters score
2. Update in-memory `this.data`
3. POST to `/scores/:judge/post`
4. **If success**: Mark as clean, update IndexedDB cache
5. **If failure**: Add to dirty scores list, update IndexedDB cache

### Score Entry (Offline)

1. User enters score
2. Update in-memory `this.data`
3. POST fails (network unavailable)
4. Add to dirty scores list in IndexedDB
5. Continue allowing more entries

### Reconnection (Offline → Online)

1. Detect network connectivity restored
2. Fetch dirty scores list from IndexedDB
3. Batch upload: `POST /scores/:judge/batch_scores` with all dirty scores
4. Server processes batch (empty scores may trigger deletion based on `assign_judges`)
5. Clear dirty scores list
6. Fetch fresh data from `/scores/:judge/heats.json`
7. Update cache and in-memory data
8. Back in sync

## API Endpoints

### Version Check Endpoint

```ruby
GET /scores/:judge/version/:heat_number
```

**Response**:
```json
{
  "heat_number": 42,
  "max_updated_at": "2025-11-06T15:30:00.123Z",
  "heat_count": 142
}
```

**Notes**:
- `heat_number` in URL (not query string) for logging purposes
- Heat number not needed for response, but helps scanning logs
- `max_updated_at`: Latest `updated_at` from heats table
- `heat_count`: Total count of heats (handles deletions)
- **Scope to judge**: Could add `judge_heat_count` to detect changes specific to this judge
- **Explicitly exclude**: `score_updated_at` - other judges' scores should NOT invalidate cache

### Batch Score Upload Endpoint

```ruby
POST /scores/:judge/batch_scores
```

**Request**:
```json
{
  "scores": [
    {
      "heat": 281110143,
      "score": "5",
      "comments": "Great technique",
      "good": "1,2,3",
      "bad": ""
    },
    {
      "heat": 281110144,
      "score": "",
      "comments": "",
      "good": "",
      "bad": ""
    }
  ]
}
```

**Processing**:
- Process each score in transaction
- Empty scores (no value, no comments, no good/bad) may trigger deletion
- Deletion behavior depends on `Event.assign_judges`:
  - If `assign_judges > 0`: Keep empty score (indicates assignment)
  - If `assign_judges == 0`: Delete empty score (no data)

## Data Structures

### IndexedDB Schema

```javascript
{
  judge_id: 798993095,
  data: { /* full heat data */ },
  timestamp: 1699300000000,
  version: {
    max_updated_at: "2025-11-06T15:30:00.123Z",
    heat_count: 142
  },
  dirty_scores: [
    {
      heat: 281110143,
      score: "5",
      comments: "Great",
      good: "1,2,3",
      bad: "",
      timestamp: 1699300100000  // When score was entered
    }
  ]
}
```

**Dirty Scores Notes**:
- Array of score objects (not a queue)
- If score updated 3 times, only final result stored
- Dirty scores treated like "dirty pages in memory"
- Last update wins (no conflict resolution needed)

## Implementation Plan

### Phase 1: Version Check Infrastructure

1. ✅ Create version check endpoint in `ScoresController`
   - Route: `GET /scores/:judge/version/:heat_number`
   - Return `max_updated_at` and `heat_count`

2. ✅ Update `HeatDataManager` to store version metadata
   - Add `version` field to IndexedDB schema
   - Store version with heat data on fetch
   - **Remove timestamp-based staleness check** (`isStale()` method)
   - Replace with version-based freshness check

3. ✅ Implement version comparison logic
   - Method: `isVersionCurrent(cachedVersion, serverVersion)`
   - Compare `max_updated_at` and `heat_count`
   - Return true if versions match, false if refresh needed

### Phase 2: Heat Navigation with Version Check

1. ✅ Modify `HeatPage.navigateToHeat()` to check version first
   - Fetch version from server
   - Compare with cached version
   - Conditionally fetch full data

2. ✅ Handle offline scenario
   - Catch network errors
   - Fall back to cached data
   - Show offline indicator (optional)

### Phase 3: Dirty Scores Tracking

1. ✅ Add dirty scores list to IndexedDB schema
   - Array of score objects
   - Deduplicate by heat ID (last update wins)

2. ✅ Update score POST handlers to track failures
   - On success: remove from dirty list
   - On failure: add/update in dirty list

3. ✅ Update `handleScoreUpdate()` to manage dirty list
   - Always update in-memory data
   - Update dirty list on POST failure

### Phase 4: Batch Upload on Reconnection

1. ✅ Create batch upload endpoint
   - Route: `POST /scores/:judge/batch_scores`
   - Process array of scores in transaction
   - Handle empty score deletion logic

2. ✅ Implement reconnection detection
   - Listen for online event: `window.addEventListener('online')`
   - Or retry on next navigation if dirty scores exist

3. ✅ Implement batch upload flow
   - Fetch dirty scores from IndexedDB
   - POST to batch endpoint
   - Clear dirty scores on success
   - Re-fetch full data to sync

### Phase 5: Testing & Edge Cases

1. ✅ Test version check performance
   - Ensure sub-100ms response time
   - Log heat numbers for analysis

2. ✅ Test offline scenarios
   - Score entry while offline
   - Navigation while offline
   - Reconnection and sync

3. ✅ Test concurrent updates
   - Multiple judges scoring same heat
   - Scratches during judging session
   - Heat additions/deletions

## IndexedDB Resource Management

### Connection Lifecycle Strategy

To prevent blocking issues when multiple tabs/windows are open and to minimize resource usage, implement a combined approach:

1. **Close on Tab Hidden** (Page Visibility API)
   - Immediately close IndexedDB connection when tab becomes hidden
   - Prevents long-running connections from blocking upgrades in other tabs
   - User switching away indicates they're not actively using this tab

2. **Close on Inactivity** (5-minute timeout)
   - Track last score update operation (not mouse movements)
   - Close connection after 5 minutes of no score updates
   - Reset timer on any `storeHeatData()` or dirty scores write
   - Allows judge to read/review without closing, but closes if truly idle

### Implementation Pattern

```javascript
class HeatDataManager {
  constructor() {
    this.db = null;
    this.inactivityTimer = null;
    this.INACTIVITY_TIMEOUT = 5 * 60 * 1000; // 5 minutes

    // Close immediately when tab hidden
    document.addEventListener('visibilitychange', () => {
      if (document.hidden && this.db) {
        console.log('[HeatDataManager] Tab hidden, closing IndexedDB');
        this.closeDB();
      }
    });
  }

  closeDB() {
    if (this.db) {
      console.log('[HeatDataManager] Closing IndexedDB connection');
      this.db.close();
      this.db = null;
    }
    this.clearInactivityTimer();
  }

  clearInactivityTimer() {
    if (this.inactivityTimer) {
      clearTimeout(this.inactivityTimer);
      this.inactivityTimer = null;
    }
  }

  resetInactivityTimer() {
    this.clearInactivityTimer();
    this.inactivityTimer = setTimeout(() => {
      console.log('[HeatDataManager] Inactivity timeout, closing IndexedDB');
      this.closeDB();
    }, this.INACTIVITY_TIMEOUT);
  }

  async ensureOpen() {
    if (!this.db) {
      await this.init();
    }
    return this.db;
  }

  async storeHeatData(judgeId, data) {
    await this.ensureOpen();
    // ... write operation ...
    this.resetInactivityTimer();
  }

  async storeDirtyScores(judgeId, dirtyScores) {
    await this.ensureOpen();
    // ... write operation ...
    this.resetInactivityTimer();
  }
}
```

### Benefits

- **Prevents blocking**: Tabs not actively scoring won't block upgrades
- **Resource efficiency**: Connections closed when not needed
- **Low overhead**: Only tracks score updates (low frequency events)
- **Seamless UX**: Automatically reopens when needed via `ensureOpen()`

### Tradeoffs

- **Slight delay on reopen**: ~10-50ms to reopen after idle/hidden
- **Acceptable**: Score updates already have network latency (100-500ms)
- **Read operations unaffected**: Version checks don't require IndexedDB

## Edge Cases & Considerations

### Scratch During Session

**Scenario**: Judge A is viewing Heat 10. Heat 10 gets scratched by organizer.

**Behavior**:
- Judge A navigates to Heat 11
- Version check detects change (`max_updated_at` updated)
- Full data re-fetched
- Heat 10 now shows as scratched

### Multiple Windows/Tabs

**Scenario**: Same judge, same browser, multiple tabs open

**Current Behavior**: Each tab has independent in-memory data, shares IndexedDB

**With This Plan**:
- Each tab checks version independently
- All tabs share same dirty scores list in IndexedDB
- Could lead to duplicate score POSTs (acceptable - last write wins)
- **Future Enhancement**: Use BroadcastChannel to sync tabs

### Version Check Failure

**Scenario**: Version endpoint times out or errors

**Behavior**:
- Treat as offline scenario
- Use cached data
- Continue allowing score entry (goes to dirty list)

### Stale Cache with No Network

**Scenario**: Judge opens app with 2-day-old cached data, no network

**Behavior**:
- Use cached data (only option available)
- Show warning about offline mode (optional)
- Sync when network available

## Logging & Observability

### Server Logs

Version endpoint includes heat number for scanning:
```
GET /scores/798993095/version/42 → 200 OK (5ms)
GET /scores/798993095/version/43 → 200 OK (4ms)
```

Quickly see which heats are being scored at any time.

### Client Logs

```
[HeatPage] Version check: cached=2025-11-06T15:00:00Z server=2025-11-06T15:30:00Z → REFETCH
[HeatPage] Version check: cached=2025-11-06T15:30:00Z server=2025-11-06T15:30:00Z → USE CACHE
[HeatPage] Version check failed, using cached data (OFFLINE)
[HeatPage] Reconnected, uploading 5 dirty scores
```

## Success Metrics

1. **Bandwidth Reduction**: 90%+ of navigations use cached data (version check only)
2. **Sync Accuracy**: 100% of scratches/changes reflected within 1 navigation
3. **Offline Support**: Scores entered offline successfully sync when reconnected
4. **Performance**: Version check < 100ms, full fetch < 500ms

## Offline Navigation Guard

### Problem

When a judge is offline and navigates away from the SPA (e.g., clicks a link to `/events` or uses browser back button), they cannot access non-SPA pages and may not be able to return to the scoring interface without network connectivity.

### Solution: Navigation Confirmation Dialog

Intercept navigation attempts when offline and show a confirmation dialog before allowing the user to leave.

**Implementation**:

```javascript
// In HeatPage or app initialization
class OfflineNavigationGuard {
  constructor() {
    this.isOffline = !navigator.onLine;

    // Track online/offline state
    window.addEventListener('online', () => {
      this.isOffline = false;
      console.log('[OfflineGuard] Online - navigation unrestricted');
    });

    window.addEventListener('offline', () => {
      this.isOffline = true;
      console.log('[OfflineGuard] Offline - navigation guard active');
    });

    // Intercept Turbo navigation
    document.addEventListener('turbo:before-visit', (event) => {
      if (this.isOffline && !this.isSPARoute(event.detail.url)) {
        const confirmed = confirm(
          "You're currently offline. If you leave this page, you may not be able to return until you're back online.\n\n" +
          "Are you sure you want to leave?"
        );

        if (!confirmed) {
          event.preventDefault();
        }
      }
    });
  }

  isSPARoute(url) {
    // Check if URL is within SPA routes
    const pathname = new URL(url, window.location.origin).pathname;
    return pathname.match(/^\/scores\/\d+\/spa/);
  }
}

// Initialize guard
new OfflineNavigationGuard();
```

**Scope of Protected Routes**:
- SPA routes: `/scores/:judge/spa*` - navigation within SPA is allowed
- External routes: Everything else requires confirmation when offline

**User Experience**:
- Online: No disruption, navigation works normally
- Offline: Browser-native confirm dialog warns before leaving SPA
- Simple, clear messaging: "You may not be able to return"

**Benefits**:
- ✅ Simple implementation (~30 lines of code)
- ✅ No service worker complexity
- ✅ No additional caching/state management
- ✅ Works with Turbo navigation
- ✅ Can be enhanced later with service worker if needed

**Limitations**:
- ⚠️ Can't intercept hard refreshes (F5/Cmd+R)
- ⚠️ Can't intercept direct URL changes in address bar
- ⚠️ Browser back button may bypass Turbo (use `beforeunload` for full coverage)

**Full Coverage Option**:

```javascript
// Additional coverage for browser navigation
window.addEventListener('beforeunload', (event) => {
  if (this.isOffline && !this.isSPARoute(window.location.href)) {
    event.preventDefault();
    event.returnValue = ''; // Required for Chrome
  }
});
```

## Future Enhancements

1. **Service Worker Safety Net**: Cache SPA shell and show "You're offline, return to scoring" fallback page when navigation fails. Provides emergency recovery without managing application state.
2. **BroadcastChannel**: Sync multiple tabs in same browser
3. **WebSocket Updates**: Push scratches/changes to active judges (no polling)
4. **Conflict Resolution**: Handle rare edge cases of conflicting updates
5. **Smart Preloading**: Prefetch likely next heat during current heat scoring
6. **Judge-Scoped Versions**: Track versions per judge to reduce unnecessary refetches
