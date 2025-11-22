# ERB→Prism Converter Integration Status

## Architecture Decision

After comparing three approaches for offline judge scoring:

1. **Web Components SPA**: 4,025 lines, complex (Shadow DOM, lifecycles)
2. **Turbo MVC with hand-written templates**: 2,604 lines, but incomplete scoring views + dual maintenance
3. **ERB→Prism Converter + Minimal Turbo**: Simplest, single source of truth

**Chosen**: #3 - ERB→Prism converter with selective components from Turbo MVC spike

## What We Have

### ✅ ERB→Prism Converter (Complete)
**Location**: `lib/erb_prism_converter.rb` (533 lines)
- Compiles ERB → Ruby → Prism AST → JavaScript
- Handles all Ruby patterns found in scoring templates
- 14 unit tests passing
- 3 template validation tests passing
- All 4 heat types convert successfully

**Template Endpoint**: `/templates/scoring.js`
- Serves converted templates as ES module
- Functions: `soloHeat()`, `rankHeat()`, `tableHeat()`, `cardsHeat()`

### ✅ Proven Utilities (From turbo-mvc-spike)
**Total**: 405 lines of battle-tested code

1. **DirtyScoresQueue** (`app/javascript/lib/dirty_scores_queue.js` - 230 lines)
   - IndexedDB-based offline score persistence
   - Automatic upload when connectivity returns
   - Comprehensive queue management API

2. **SubjectSorter** (`app/javascript/lib/subject_sorter.js` - 111 lines)
   - Handles subject sorting by judge preferences
   - Supports back number, couple name, studio name sorting

3. **Service Worker** (`public/service-worker.js` - 64 lines)
   - Network-first caching strategy
   - Offline API response fallback

### ✅ Basic Heat Controller (Needs Enhancement)
**Location**: `app/javascript/controllers/heat_app_controller.js` (140 lines)
- Loads converter-generated templates
- Fetches heat data from JSON endpoints
- Renders using appropriate template function
- TODO: Add offline support, score posting, navigation

## What We Need

### 1. Enhance Heat Controller with Offline Support
**Estimated**: ~150 lines

```javascript
import { DirtyScoresQueue } from 'lib/dirty_scores_queue'

class HeatAppController {
  async connect() {
    this.queue = new DirtyScoresQueue()
    await this.queue.init()

    // Set up online/offline handlers
    window.addEventListener('online', () => this.handleOnline())
    window.addEventListener('offline', () => this.handleOffline())
  }

  async handleOnline() {
    // Upload queued scores
    const csrfToken = document.querySelector('[name="csrf-token"]').content
    await this.queue.uploadAll(csrfToken)
  }

  async postScore(heatId, scoreData) {
    try {
      // Try to post immediately
      await this.sendScore(heatId, scoreData)
    } catch (error) {
      // Queue for later if offline
      await this.queue.add({ heat_id: heatId, ...scoreData })
    }
  }
}
```

### 2. Add Score Posting Logic
**Estimated**: ~100 lines
- Attach event listeners to form inputs
- POST scores to `/heats/:id/score`
- Queue when offline
- Visual feedback on save

### 3. Add Turbo Navigation Interception (Optional)
**Estimated**: ~100 lines
- Intercept `turbo:before-visit` for heat URLs
- Render from in-memory cache when offline
- Update URL with `history.pushState`

This is **optional** - the current approach works without Turbo interception since we're already loading templates dynamically.

### 4. Add Heat List Rendering
**Estimated**: ~50 lines
- Create heat list template (or convert ERB partial)
- Render list in `showHeatList()`
- Add navigation to individual heats

### 5. Service Worker Registration
**Estimated**: ~20 lines in application layout

```javascript
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/service-worker.js')
}
```

### 6. Tests
**Estimated**: ~300 lines
- Heat controller tests
- Score posting tests
- Offline queue integration tests
- Navigation tests

## Code Comparison

### Current Status
```
ERB→Prism converter: 533 lines ✅
Templates controller: 69 lines ✅
Heat app controller: 140 lines ✅
Utilities: 405 lines ✅
Service Worker: 64 lines ✅

Total existing: ~1,211 lines
```

### To Add
```
Enhanced heat controller: ~150 lines
Score posting: ~100 lines
Heat list rendering: ~50 lines
Service Worker registration: ~20 lines
Tests: ~300 lines

Total new: ~620 lines
```

### Final Result
```
Complete offline solution: ~1,831 lines

vs Web Components: ~4,025 lines (-54%)
vs Turbo MVC spike: ~2,604 lines (-30%)
vs Original ERB/Stimulus: ~1,258 lines (+45% for full offline)
```

## Key Advantages

1. **Single Source of Truth**: ERB partials are canonical
2. **Zero Dual Maintenance**: Changes to ERB automatically reflected in JavaScript
3. **Simpler Architecture**: No hand-written renderers, no complex orchestration
4. **Proven Components**: Utilities battle-tested in turbo-mvc-spike
5. **Complete Coverage**: Converter handles all 4 heat types automatically
6. **Lowest Complexity**: 30% less code than turbo-mvc-spike, 54% less than Web Components

## Next Steps

1. ✅ Copy proven utilities from turbo-mvc-spike
2. ⬜ Add offline score queueing to heat controller
3. ⬜ Implement score posting with DirtyScoresQueue
4. ⬜ Add heat list rendering
5. ⬜ Register Service Worker
6. ⬜ Write comprehensive tests
7. ⬜ Test with actual event database
8. ⬜ Production deployment validation

## Success Criteria

- ✅ All 4 heat types render correctly (via converter)
- ⬜ Scores can be entered and saved
- ⬜ Scores queue when offline
- ⬜ Queued scores upload when connectivity returns
- ⬜ Heat navigation works offline (cached in Service Worker)
- ⬜ All tests passing
- ⬜ Production validation at live event
