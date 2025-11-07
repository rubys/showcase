# SPA Offline Scoring - Unified Implementation Plan

**Status:** In Development
**Last Updated:** 2025-11-06
**Branch:** `spa-custom-elements`

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Current Implementation Status](#current-implementation-status)
- [Heat Type Support](#heat-type-support)
- [Sync Strategy](#sync-strategy)
- [Slot Navigation](#slot-navigation)
- [Edge Cases & Limitations](#edge-cases--limitations)
- [Deployment Strategy](#deployment-strategy)
- [Testing Plan](#testing-plan)
- [Success Criteria](#success-criteria)
- [Performance Data](#performance-data)

---

## Overview

### Goal

Enable judges to continue scoring heats when internet connectivity is lost during an event. Eliminate the complexity of service workers by using a Single Page Application (SPA) architecture with Custom Elements and IndexedDB for offline support.

### Key Design Decisions

1. **Single JSON download**: All heat data fetched once from `/scores/:judge/heats.json`
2. **Custom Elements rendering**: Client-side components render heats (no ERB duplication)
3. **Version-based sync**: Lightweight version checks detect server-side changes
4. **Batch score uploads**: Dirty scores uploaded in single transaction when online
5. **No service worker**: Simpler architecture, easier debugging, better performance

### Approach Summary

```
Online:   GET /scores/:judge/heats.json → Store in IndexedDB
          Render heats client-side via Custom Elements
          POST scores individually → Update IndexedDB

Offline:  Render from IndexedDB cache
          Queue scores as "dirty" → Store in IndexedDB

Back Online: POST /scores/:judge/batch → Sync all dirty scores
             GET version check → Refresh if stale
```

---

## Architecture

### Component Structure

```
app/javascript/
├── components/
│   ├── heat-page.js              # Orchestrator
│   ├── shared/
│   │   ├── heat-header.js        # Heat number, category, dance
│   │   ├── heat-info-box.js      # Instructions/shortcuts
│   │   └── heat-navigation.js    # Prev/next buttons
│   └── heat-types/
│       ├── heat-solo.js          # Solo performances ✅
│       ├── heat-rank.js          # Finals/scrutineering ⚠️
│       ├── heat-table.js         # Radio buttons/table ✅
│       └── heat-cards.js         # Drag-and-drop ✅
└── helpers/
    └── heat_data_manager.js      # IndexedDB wrapper
```

### Data Flow

**Initial Load (Online):**
```
1. GET /scores/:judge/spa → Render SPA shell
2. GET /scores/:judge/heats.json → Fetch all heat data (~60-105KB gzipped)
3. Store in IndexedDB with version metadata
4. Render first heat using Custom Elements
```

**Navigation (Online):**
```
1. GET /scores/:judge/version/:heat → Lightweight version check
2. If version matches cached: Use IndexedDB (no fetch)
3. If version changed: Re-fetch /scores/:judge/heats.json, update cache
4. Render heat from in-memory data
```

**Navigation (Offline):**
```
1. Version check fails (network error)
2. Use cached data from IndexedDB
3. Render heat from cache
4. Continue scoring (queue as dirty)
```

**Score Submission (Online):**
```
1. User enters score
2. POST /scores/:judge/post → Immediate save
3. Update IndexedDB cache
4. Clear dirty flag if set
```

**Score Submission (Offline):**
```
1. User enters score
2. Update in-memory data
3. Add to dirty scores list in IndexedDB
4. Continue scoring
```

**Reconnection (Offline → Online):**
```
1. Detect network connectivity
2. Fetch dirty scores from IndexedDB
3. POST /scores/:judge/batch → All dirty scores in single transaction
4. Clear dirty scores list
5. GET /scores/:judge/heats.json → Fresh data
6. Update cache
```

### IndexedDB Schema

**Database:** `showcase_heats`

**Object Store:** `heats`
```javascript
{
  judge_id: 798993095,
  data: { /* full heat data from JSON */ },
  timestamp: 1699300000000,
  version: {
    max_updated_at: "2025-11-06T15:30:00.123Z",
    heat_count: 142
  },
  dirty_scores: [
    {
      heat_id: 281110143,
      slot: 1,
      score: "5",
      comments: "Great technique",
      good: "1,2,3",
      bad: "",
      timestamp: 1699300100000
    }
  ]
}
```

**Connection Lifecycle:**
- Close on tab hidden (Page Visibility API)
- Close after 5 minutes of inactivity (no score updates)
- Auto-reopen via `ensureOpen()` when needed
- Prevents blocking issues with multiple tabs

---

## Current Implementation Status

### ✅ Completed

**Infrastructure:**
- JSON endpoint: `GET /scores/:judge/heats.json`
- SPA route: `GET /scores/:judge/spa`
- IndexedDB manager (`heat_data_manager.js`)
- Heat page orchestrator (`heat-page.js`)

**Heat Type Components:**
- ✅ **Solo heats** - Working
- ✅ **Cards heats** - Drag-and-drop working
- ✅ **Radio button/table heats** - Working

**Navigation:**
- ✅ Prev/Next buttons functional
- ✅ URL parameter handling (heat number)
- ✅ Parallel routes working (SPA + ERB coexist)

**Score Persistence:**
- ✅ Scores POST to server successfully
- ✅ In-memory data updates during navigation
- ✅ Score changes persist across page refresh

### 🚧 In Progress

**Sync Strategy:**
- ⚠️ Version check endpoint needed
- ⚠️ Batch upload endpoint needed
- ⚠️ Dirty score tracking needs implementation
- ⚠️ Online/offline detection needed

**Navigation:**
- ⚠️ **Slot navigation** - Spec complete, implementation needed (see [Slot Navigation](#slot-navigation))
- ⚠️ Multi-dance heat support incomplete

**Heat Types:**
- ⚠️ **Rank/Finals** - Complex, may be documented limitation

### ❌ Not Started

- Comprehensive testing with offline scenarios
- UI polish to match original ERB design
- Performance optimization for large datasets
- Mobile/tablet testing

---

## Heat Type Support

### Solo Heats ✅

**Status:** Working

**Features:**
- Display lead, follow, instructor, studio
- Score input fields (Event.solo_scoring mode)
- Comments textarea
- Formation details if applicable

**Implementation:** `heat-types/heat-solo.js`

### Cards Heats ✅

**Status:** Working (drag-and-drop functional)

**Features:**
- Draggable back number cards
- Drop zones for scores
- Visual feedback for placement
- Score submission on drop

**Implementation:** `heat-types/heat-cards.js`

### Radio/Table Heats ✅

**Status:** Working

**Features:**
- Table with couples
- Radio buttons for callbacks/scores
- Comments per couple
- Score inputs as needed

**Implementation:** `heat-types/heat-table.js`

### Rank/Finals Heats ⚠️

**Status:** Documented Limitation

**Challenge:**
- Complex ranking input UI
- Scrutineering calculations happen server-side
- Multi-judge coordination required
- Semi-finals vs. finals slot handling

**Plan:**
- **Offline:** Allow score input, queue as dirty
- **Online:** Submit scores, but final ranking calculations happen on server
- **Limitation:** Winners not determined until online and all judges have submitted
- **Fallback:** If too complex, redirect to ERB route for Rank heats

**Decision:** Try to support basic input offline, document that final results require online connectivity.

---

## Sync Strategy

### Version Check (Online)

**Endpoint:** `GET /scores/:judge/version/:heat`

**Response:**
```json
{
  "heat_number": 42,
  "max_updated_at": "2025-11-06T15:30:00.123Z",
  "heat_count": 142
}
```

**Logic:**
```javascript
async function shouldRefresh(cachedVersion, serverVersion) {
  if (!cachedVersion) return true;

  // Check if heats were updated
  if (serverVersion.max_updated_at !== cachedVersion.max_updated_at) {
    return true;
  }

  // Check if heat count changed (additions/deletions)
  if (serverVersion.heat_count !== cachedVersion.heat_count) {
    return true;
  }

  return false;
}
```

**Notes:**
- `max_updated_at`: Latest update to any heat (detects scratches, changes)
- `heat_count`: Total heat count (detects additions/deletions)
- **Excludes** scores from other judges (their updates don't invalidate cache)
- Heat number in URL for logging/analysis purposes

### Dirty Score Tracking

**When a score is entered:**
```javascript
async function handleScoreUpdate(heatId, slot, scoreData) {
  // Always update in-memory data
  updateInMemory(heatId, slot, scoreData);

  try {
    // Try to POST to server
    await fetch(`/scores/${judgeId}/post`, {
      method: 'POST',
      body: JSON.stringify({ heat: heatId, slot, ...scoreData })
    });

    // Success: update cache, remove from dirty list
    await heatDataManager.updateScore(judgeId, heatId, slot, scoreData);
    await heatDataManager.removeDirtyScore(judgeId, heatId, slot);

  } catch (error) {
    // Network error: add to dirty list
    console.log('Offline, queuing score');
    await heatDataManager.addDirtyScore(judgeId, heatId, slot, scoreData);
  }
}
```

**Dirty Score Deduplication:**
- If same heat/slot updated multiple times offline: last update wins
- Store as object keyed by `${heatId}-${slot}`, not as array
- Automatically deduplicates

### Batch Upload (Reconnection)

**Endpoint:** `POST /scores/:judge/batch`

**Request:**
```json
{
  "scores": [
    {
      "heat": 281110143,
      "slot": 1,
      "score": "5",
      "comments": "Great",
      "good": "1,2,3",
      "bad": ""
    },
    {
      "heat": 281110144,
      "slot": 1,
      "score": "",
      "comments": "",
      "good": "",
      "bad": ""
    }
  ]
}
```

**Response:**
```json
{
  "succeeded": [
    { "heat_id": 281110143, "slot": 1 }
  ],
  "failed": [
    { "heat_id": 281110144, "slot": 1, "error": "Heat not found" }
  ]
}
```

**Processing:**
- Single database transaction (all or nothing)
- Uses `Score.find_or_create_by(judge_id:, heat_id:, slot:)` for idempotency
- Empty scores may trigger deletion (depends on `Event.assign_judges` setting)
- Partial failures handled: succeeded scores removed from dirty list, failed remain

**Reconnection Flow:**
```javascript
window.addEventListener('online', async () => {
  const dirtyScores = await heatDataManager.getDirtyScores(judgeId);

  if (dirtyScores.length === 0) return;

  try {
    const response = await fetch(`/scores/${judgeId}/batch`, {
      method: 'POST',
      body: JSON.stringify({ scores: dirtyScores })
    });

    const results = await response.json();

    // Remove succeeded scores from dirty list
    for (const success of results.succeeded) {
      await heatDataManager.removeDirtyScore(judgeId, success.heat_id, success.slot);
    }

    // Refresh full data
    await fetchAndCacheHeatData(judgeId);

    console.log(`Synced ${results.succeeded.length} scores, ${results.failed.length} failed`);
  } catch (error) {
    console.error('Batch sync failed:', error);
    // Retry later or manual sync button
  }
});
```

---

## Slot Navigation

Multi-dance heats require navigating through "slots" representing each child dance.

**Detailed specification:** See [SLOT_NAVIGATION.md](SLOT_NAVIGATION.md)

### Quick Summary

**Example:** "Bronze 2 Dance" with Waltz and Tango (heat_length = 2)

**Navigation:**
- Heat 5, Slot 1 (Waltz) → Next → Heat 5, Slot 2 (Tango)
- Heat 5, Slot 2 (Tango) → Next → Heat 6, Slot 1 (if next is Multi) or Heat 6
- Heat 5, Slot 1 (Waltz) → Prev → Heat 4, Slot N (last slot of Heat 4 if Multi) or Heat 4

**URL Structure:**
- Multi-dance: `/scores/:judge/spa?heat=5&slot=2`
- Non-multi: `/scores/:judge/spa?heat=5`

**Scrutineering:**
- If `semi_finals` enabled and subjects > 8: `max_slots = heat_length * 2`
- Slots 1-N: Semi-finals
- Slots N+1 to 2N: Finals

**Implementation Status:** ⚠️ Spec complete, JavaScript implementation needed

---

## Edge Cases & Limitations

### Session Timeout

**Scenario:**
- Judge loads SPA at 2:00 PM with valid HTTP Basic Auth session
- Judge goes offline, scores 50 heats from 2:05-4:00 PM
- Judge comes back online at 4:00 PM
- Session may have expired (unlikely with HTTP Basic Auth)

**Handling:**
- HTTP Basic Auth typically doesn't expire (browser caches credentials)
- If session does expire and POST fails with 401:
  - Show error message: "Session expired. Please refresh page to re-authenticate."
  - Keep dirty scores in IndexedDB
  - Manual page refresh triggers re-auth
  - After re-auth, dirty scores sync automatically

**Manual refresh is acceptable.**

### ActionCable (Real-time Updates)

**Scenario:**
- Judge viewing Heat 10 in SPA (has cached data)
- Organizer scratches Heat 10 via admin interface
- ActionCable broadcasts "heat 10 scratched"

**Handling:**
- Scoring pages do **not** consume ActionCable events
- ActionCable broadcasts for tally/scoreboard pages (not in this plan's scope)
- Changes detected via version check on next navigation
- Judge will see scratched heat on next navigation (when version check triggers refresh)

**No ActionCable integration needed for scoring SPA.**

### Rank/Finals Scrutineering

**Scenario:**
- Finals heat requires ranking couples (1st, 2nd, 3rd, etc.)
- Scrutineering system calculations happen server-side
- Multiple judges must submit before winners determined

**Handling:**
- **Online:** Scores submitted normally, server calculates rankings
- **Offline:** Score inputs queued as dirty, but final rankings not calculated
- **Limitation:** Final results (winners) not available until:
  1. All judges back online
  2. All scores submitted
  3. Server applies Rule 5-11 scrutineering algorithms

**Documented limitation:** Finals may require online connectivity for complete functionality.

**Fallback option:** If rank heat rendering proves too complex, detect and redirect to ERB route for rank heats only.

### Offline Navigation Guard

**Scenario:**
- Judge is offline, navigates away from SPA (clicks link to `/events` or uses browser back)
- Non-SPA pages won't load offline
- Judge can't return to scoring interface

**Handling:**
```javascript
// Intercept Turbo navigation when offline
document.addEventListener('turbo:before-visit', (event) => {
  if (!navigator.onLine && !isSPARoute(event.detail.url)) {
    const confirmed = confirm(
      "You're currently offline. If you leave this page, you may not be able to return until you're back online.\n\n" +
      "Are you sure you want to leave?"
    );
    if (!confirmed) event.preventDefault();
  }
});
```

**Simple browser-native confirmation prevents accidental navigation.**

---

## Deployment Strategy

### Phase 1: Parallel Routes (Current)

**Setup:**
- ERB route: `/scores/:judge/heat/:number` (existing)
- SPA route: `/scores/:judge/spa?heat=:number` (new)
- Both routes functional simultaneously

**Heatlist Page:**
```erb
<%= link_to "Open SPA Scoring", scores_spa_path(judge: @judge, heat: @heats.first.number),
    class: "btn btn-primary" %>
```

**User Choice:**
- Judge can use traditional ERB route (default for now)
- Judge can opt-in to SPA via button
- Both work independently

### Phase 2: Beta Testing

**Target:** 1-2 willing judges at a single event

**Monitoring:**
- Browser console logs for errors
- Network tab for performance
- Feedback from judges on UX

**Success Criteria:**
- No data loss
- Offline queueing works
- Batch sync succeeds
- Performance acceptable

### Phase 3: Broader Rollout

**After successful beta:**
- Offer SPA to all judges at an event
- Keep ERB as fallback option
- Monitor for issues

**Success Criteria:**
- 90%+ judges complete scoring without issues
- Sync success rate > 95%
- No major bugs reported

### Phase 4: ERB Retirement

**Only after 2-3 successful events:**
- Make SPA the default route
- Remove ERB templates for heat scoring
- Update heatlist to link directly to SPA
- Remove old routes from `config/routes.rb`

**No long-term dual maintenance.**

**Rollback Plan:**
- Git revert to previous commit
- Restore ERB templates
- Simple and fast

---

## Testing Plan

### Manual Testing Protocol

**Test 1: Online Normal Scoring**
```
1. Visit /scores/:judge/spa?heat=1
2. Verify heat renders correctly
3. Enter score
4. Verify POST succeeds
5. Navigate to next heat
6. Verify navigation works
```

**Test 2: Offline Queuing**
```
1. Visit /scores/:judge/spa?heat=1 (online)
2. Wait for data to cache
3. Go offline (DevTools → Network → Offline)
4. Enter scores on 5 heats
5. Verify scores queue to IndexedDB
6. Verify navigation works offline
7. Verify scores persist on refresh
```

**Test 3: Batch Sync**
```
1. Queue 10 scores offline
2. Go online
3. Verify batch sync triggers automatically
4. Verify all 10 scores in database
5. Verify dirty list cleared
```

**Test 4: Version Check**
```
1. Load SPA with cached data
2. Admin scratches a heat via admin interface
3. Navigate in SPA
4. Verify version check detects change
5. Verify fresh data fetched
6. Verify scratched heat shows correctly
```

**Test 5: Multi-dance Slots**
```
1. Navigate to multi-dance heat (e.g., "Bronze 2 Dance")
2. Verify slot 1 renders
3. Click Next
4. Verify slot 2 renders
5. Click Next
6. Verify moves to next heat
7. Navigate back to multi-dance heat
8. Click Prev from slot 1
9. Verify moves to previous heat's last slot
```

**Test 6: All Heat Types**
```
1. Test Solo heat rendering and scoring
2. Test Cards heat drag-and-drop
3. Test Radio/Table heat input
4. Test Rank heat (if implemented)
```

### Automated Testing

**Unit Tests (JavaScript):**
- HeatDataManager CRUD operations
- Dirty score deduplication logic
- Version comparison logic
- Slot navigation calculations

**Integration Tests (Rails):**
```ruby
# test/controllers/scores_controller_test.rb

test "heats.json returns complete data" do
  get heats_json_scores_path(judge: @judge), as: :json
  assert_response :success
  json = JSON.parse(response.body)
  assert json['heats'].length > 0
  assert json['judge_id']
end

test "version endpoint returns metadata" do
  get version_scores_path(judge: @judge, heat: 1), as: :json
  assert_response :success
  json = JSON.parse(response.body)
  assert json['max_updated_at']
  assert json['heat_count']
end

test "batch endpoint processes multiple scores" do
  post batch_scores_path(judge: @judge), params: {
    scores: [
      { heat: @heat1.id, slot: 1, score: "1" },
      { heat: @heat2.id, slot: 1, score: "2" }
    ]
  }, as: :json

  assert_response :success
  json = JSON.parse(response.body)
  assert_equal 2, json['succeeded'].length
  assert_equal 0, json['failed'].length
end
```

### Browser Compatibility

**Test on:**
- Chrome 80+ (desktop)
- Firefox 74+ (desktop)
- Safari 13.1+ (desktop, iPad)
- Mobile Safari (iPhone)
- Chrome Android (if available)

**Target:** Modern browsers with ES2020 support, IndexedDB, Custom Elements

---

## Success Criteria

### Functional Requirements

- ✅ All heat types render correctly (Solo, Cards, Radio/Table)
- ⚠️ Rank heats render or redirect to ERB with clear messaging
- ✅ Navigation works (prev/next)
- ⚠️ Multi-dance slot navigation works correctly
- ✅ Scores submit successfully online
- ⚠️ Scores queue when offline
- ⚠️ Scores sync when returning online
- ✅ Works on target browsers

### Performance Requirements

- ✅ Initial JSON download < 1 second on 3G (validated: 60-105KB gzipped)
- ⚠️ Time to first render < 1 second
- ⚠️ Heat navigation < 100ms
- ⚠️ Memory usage < 50MB

### Reliability Requirements

- 99%+ sync success rate
- No data loss (dirty scores persisted)
- Handles 100+ queued scores
- Recovers from errors gracefully

### Usability Requirements

- No training required for judges
- Clear online/offline indicators (if applicable)
- Obvious sync status
- Error messages are actionable
- No perceivable slowdown vs. ERB

---

## Performance Data

### JSON Payload Size (Validated)

**Measurements from production databases:**

| Event | Heats | Raw JSON | Gzipped | Per Heat (Gzipped) |
|-------|-------|----------|---------|-------------------|
| Montgomery-Lincolnshire | 251 | 1.04MB | **69.9KB** | 285B |
| San Jose September | 435 | 991KB | **60.3KB** | 141B |

**Compression:** 93.4-93.9% (gzip)

**Download time @ 3G (1.6 Mbps):**
- 69.9KB = ~420ms
- 105KB = ~525ms

**Memory usage estimate:**
- Raw JSON: 1.0-1.5MB
- Parsed object: 2-3MB
- IndexedDB: 1.5MB
- **Total: ~4-5MB** (trivial for modern devices)

**Conclusion:** JSON size is **not a blocker**. Performance is excellent.

**Full analysis:** [JSON_SIZE_ANALYSIS.md](JSON_SIZE_ANALYSIS.md)

### Bandwidth Comparison

**Service Worker Approach (OFFLINE_SCORING_PLAN.md):**
- 251 separate HTML page fetches
- ~200-400KB gzipped total
- Cache hits reduce subsequent loads

**SPA Approach (this plan):**
- Single JSON fetch: 60-105KB gzipped
- **2-5x more efficient**

---

## Implementation Checklist

### Backend

- [ ] Create version check endpoint: `GET /scores/:judge/version/:heat`
- [ ] Create batch upload endpoint: `POST /scores/:judge/batch`
- [ ] Add tests for new endpoints
- [ ] Ensure idempotent score updates (already exists)

### Frontend - Sync Strategy

- [ ] Implement version comparison logic
- [ ] Implement dirty score tracking in HeatDataManager
- [ ] Add batch upload on reconnection
- [ ] Add online/offline event listeners
- [ ] Test dirty score deduplication

### Frontend - Slot Navigation

- [ ] Implement slot navigation algorithm (see SLOT_NAVIGATION.md)
- [ ] Update HeatNavigation component for slot display
- [ ] Handle URL parameters: `?heat=5&slot=2`
- [ ] Test all edge cases (boundary, scrutineering, etc.)

### Frontend - Heat Types

- [ ] Polish Solo heat component
- [ ] Polish Cards heat component
- [ ] Polish Radio/Table heat component
- [ ] Implement or document limitation for Rank heats

### Frontend - UI/UX

- [ ] Match CSS from original ERB templates
- [ ] Add loading indicators
- [ ] Add offline indicator (optional)
- [ ] Add keyboard shortcuts
- [ ] Test on mobile/tablet

### Testing

- [ ] Write unit tests for HeatDataManager
- [ ] Write integration tests for endpoints
- [ ] Manual testing protocol (see above)
- [ ] Browser compatibility testing
- [ ] Performance testing with production data

### Deployment

- [ ] Add SPA button to heatlist page
- [ ] Deploy to production
- [ ] Beta test with 1-2 judges
- [ ] Monitor and iterate
- [ ] Broader rollout
- [ ] Retire ERB (after 2-3 successful events)

---

## Next Steps

1. **Implement slot navigation** - High priority, spec is complete
2. **Build version check endpoint** - Backend work
3. **Build batch upload endpoint** - Backend work
4. **Implement dirty score tracking** - Frontend work
5. **Test offline scenarios** - Manual testing
6. **Polish UI** - Match ERB design
7. **Deploy and beta test** - Real-world validation

---

## Appendix

### Related Documents

- [SLOT_NAVIGATION.md](SLOT_NAVIGATION.md) - Detailed slot navigation specification
- [JSON_SIZE_ANALYSIS.md](JSON_SIZE_ANALYSIS.md) - Performance measurements

### Historical Context

This plan consolidates and supersedes:
- `OFFLINE_SCORING_PLAN.md` - Service worker approach (fully implemented on separate branch, archived)
- `SPA_SCORING_PLAN.md` - Original SPA design (merged into this plan)
- `SPA_SYNC_STRATEGY.md` - Sync strategy refinement (merged into this plan)

All previous plans available in Git history.

### Key Differences from Service Worker Approach

| Aspect | Service Worker | SPA (This Plan) |
|--------|---------------|-----------------|
| Page Caching | 251 HTML pages | Single JSON (60-105KB) |
| Bandwidth | 200-400KB | 60-105KB (2-5x better) |
| Rendering | ERB + JavaScript | JavaScript only |
| Debugging | Complex (cache states) | Simple (inspect IndexedDB) |
| Maintenance | Dual code paths | Single codebase |
| Performance | Good | Excellent |

**SPA is the clear winner.**
