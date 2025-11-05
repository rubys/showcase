# SPA Scoring Implementation Plan

**Status:** Planning - Ready for Implementation
**Last Updated:** 2025-01-05
**Authors:** Sam Ruby, Claude Code

## Table of Contents

- [Overview](#overview)
- [Goals](#goals)
- [Architecture](#architecture)
- [Component Structure](#component-structure)
- [Implementation Phases](#implementation-phases)
- [Data Model](#data-model)
- [Migration Strategy](#migration-strategy)
- [Files to Retire](#files-to-retire)
- [Testing Strategy](#testing-strategy)
- [Future Phases](#future-phases)

---

## Overview

Convert judge scoring pages from server-side ERB rendering to client-side web components using Custom Elements. This enables:
- Single bulk JSON download instead of 251 separate page requests
- Same codebase works online and offline (no service worker complexity)
- Data stored in IndexedDB for offline access
- Simpler architecture with predictable state management

This plan covers **judge scoring only**. DJ and emcee pages will be converted in future phases using the same patterns established here.

---

## Goals

### Primary Goals
1. **Eliminate service worker complexity** - No cache state management, easier debugging
2. **Single data download** - One JSON request instead of 251 HTML pages
3. **Unified codebase** - Same rendering code works online and offline
4. **Maintain functionality** - All existing scoring features work identically
5. **Keep modularity** - Preserve existing ERB split (don't create one huge file)

### Non-Goals
- Convert entire application to SPA (only scoring-critical pages)
- Change scoring UI/UX (keep existing design)
- Rewrite non-scoring pages (heatlist index, reports, admin, etc. stay as ERB)

---

## Architecture

### Current (Server-Side Rendering)
```
Browser → GET /scores/55/heat/1 → Rails renders ERB → HTML → Browser displays
         → GET /scores/55/heat/2 → Rails renders ERB → HTML → Browser displays
         → ... (251 times)
```

### Proposed (Client-Side Rendering)
```
Browser → GET /scores/55/heats.json → Rails returns JSON → Store in IndexedDB
         ↓
    JavaScript renders heat based on URL
         ↓
    <heat-page> component
         ├→ Reads data from IndexedDB
         ├→ Determines heat type (solo/rank/table/cards)
         └→ Renders appropriate sub-components
```

### Online vs Offline
- **Online**: Fetch JSON from server, store in IndexedDB, render
- **Offline**: Read from IndexedDB, render
- **Sync**: POST individual scores to server, update IndexedDB
- **Refresh**: GET fresh JSON if stale or on demand

---

## Component Structure

### Directory Layout
```
app/javascript/components/
├── heat-page.js              # Top-level orchestrator
├── shared/                   # Shared components used by all heat types
│   ├── heat-header.js        # Heat number, category, dance name
│   ├── heat-info-box.js      # Instructions/keyboard shortcuts
│   └── heat-navigation.js    # Prev/next buttons, heat jumper
└── heat-types/               # Different scoring modes
    ├── heat-solo.js          # Solo performances
    ├── heat-rank.js          # Finals with ranking
    ├── heat-table.js         # Standard table view
    └── heat-cards.js         # Card-based drag-and-drop
```

### Component Hierarchy
```
<heat-page heat-number="1" judge-id="55">
  │
  ├─ <heat-header>            # Shared across all types
  ├─ <heat-info-box>          # Shared across all types
  │
  ├─ ONE OF:
  │   ├─ <heat-solo>          # For solo heats
  │   ├─ <heat-rank>          # For finals
  │   ├─ <heat-table>         # For regular heats (callbacks, etc)
  │   └─ <heat-cards>         # For card-based scoring
  │
  └─ <heat-navigation>        # Shared across all types
```

### Component Responsibilities

**`heat-page.js`** (Orchestrator)
- Parse URL to get heat number and judge ID
- Fetch heat data from IndexedDB
- Determine heat type (solo/rank/table/cards based on data)
- Render appropriate child components
- Handle URL changes (browser back/forward)
- Coordinate score submissions

**`shared/heat-header.js`**
- Display heat number, category, dance name
- Show ballroom if applicable
- Show multi-dance compilation info

**`shared/heat-info-box.js`**
- Display keyboard shortcuts
- Show scoring instructions
- Render tips/warnings

**`shared/heat-navigation.js`**
- Previous/Next heat buttons
- Heat number selector
- Return to heatlist link
- Keyboard navigation (arrow keys)

**`heat-types/heat-solo.js`**
- Render solo performance details
- Show lead, follow, instructor, studio
- Score input fields (4-part or simple)
- Comments textarea
- Formation details if applicable

**`heat-types/heat-rank.js`**
- Render finalists table
- Ranking dropdowns or inputs
- Callback checkboxes if semi-finals
- Handle skating system calculations

**`heat-types/heat-table.js`**
- Render couples in table format
- Radio buttons for callbacks
- Score inputs
- Comments per couple
- Group by dance/category/studio as needed

**`heat-types/heat-cards.js`**
- Render draggable back number cards
- Drag-and-drop zones for scores
- Visual feedback for placement
- Score submission on drop

---

## Implementation Phases

### Phase 1: Infrastructure (4-6 hours)

**Goal:** Set up JSON API and IndexedDB foundation

#### Tasks

1. **Create JSON Endpoint** (`app/controllers/scores_controller.rb`)
   ```ruby
   # GET /scores/:judge/heats.json
   def heats_json
     judge = Person.find(params[:judge].to_i)

     heats = Heat.all.where(number: 1..)
       .order(:number)
       .includes(
         dance: [:open_category, :closed_category, :multi_category,
                 {solo_category: :extensions}, :multi_children],
         entry: [:lead, :follow, :instructor, :studio, :age, :level],
         solo: [:category_override, :song, formations: :person],
         scores: []
       )

     render json: {
       judge_id: judge.id,
       judge_name: judge.name,
       event: {
         name: Event.current.name,
         settings: {
           open_scoring: Event.current.open_scoring,
           closed_scoring: Event.current.closed_scoring,
           solo_scoring: Event.current.solo_scoring,
           judge_comments: Event.current.judge_comments,
           column_order: Event.current.column_order,
           # ... other event settings needed for rendering
         }
       },
       heats: heats.group_by(&:number).map do |number, heat_group|
         heat = heat_group.first
         {
           number: number,
           category: heat.category,
           dance: heat.dance.name,
           # ... full heat data serialization
         }
       end
     }
   end
   ```

2. **Add Route** (`config/routes.rb`)
   ```ruby
   get '/scores/:judge/heats', to: 'scores#heats_json',
       defaults: { format: :json }, as: 'judge_heats_json'
   ```

3. **Create Heat Data Manager** (`app/javascript/helpers/heat_data_manager.js`)
   ```javascript
   class HeatDataManager {
     constructor() {
       this.dbName = 'showcase_heats';
       this.storeName = 'heats';
     }

     async open() {
       return new Promise((resolve, reject) => {
         const request = indexedDB.open(this.dbName, 1);

         request.onerror = () => reject(request.error);
         request.onsuccess = () => resolve(request.result);

         request.onupgradeneeded = (event) => {
           const db = event.target.result;
           if (!db.objectStoreNames.contains(this.storeName)) {
             const store = db.createObjectStore(this.storeName,
               { keyPath: 'judge_id' });
             store.createIndex('timestamp', 'timestamp');
           }
         };
       });
     }

     async storeHeatData(judgeId, data) {
       const db = await this.open();
       return new Promise((resolve, reject) => {
         const tx = db.transaction(this.storeName, 'readwrite');
         const store = tx.objectStore(this.storeName);

         const record = {
           judge_id: judgeId,
           data: data,
           timestamp: Date.now()
         };

         const request = store.put(record);
         request.onsuccess = () => resolve();
         request.onerror = () => reject(request.error);
       });
     }

     async getHeatData(judgeId) {
       const db = await this.open();
       return new Promise((resolve, reject) => {
         const tx = db.transaction(this.storeName, 'readonly');
         const store = tx.objectStore(this.storeName);
         const request = store.get(judgeId);

         request.onsuccess = () => {
           const result = request.result;
           resolve(result ? result.data : null);
         };
         request.onerror = () => reject(request.error);
       });
     }

     async getHeat(judgeId, heatNumber) {
       const data = await this.getHeatData(judgeId);
       if (!data) return null;

       return data.heats.find(h => h.number === heatNumber);
     }

     async isStale(judgeId, maxAgeMs = 3600000) { // 1 hour default
       const db = await this.open();
       return new Promise((resolve, reject) => {
         const tx = db.transaction(this.storeName, 'readonly');
         const store = tx.objectStore(this.storeName);
         const request = store.get(judgeId);

         request.onsuccess = () => {
           const result = request.result;
           if (!result) {
             resolve(true); // No data = stale
           } else {
             const age = Date.now() - result.timestamp;
             resolve(age > maxAgeMs);
           }
         };
         request.onerror = () => reject(request.error);
       });
     }
   }

   window.heatDataManager = new HeatDataManager();
   ```

4. **Import in Application** (`app/javascript/application.js`)
   ```javascript
   import "helpers/heat_data_manager"
   ```

**Deliverables:**
- ✅ JSON endpoint returns all heat data for a judge
- ✅ IndexedDB manager stores/retrieves heat data
- ✅ Data manager available globally as `window.heatDataManager`

**Testing:**
- [ ] Visit `/scores/55/heats.json` - verify JSON structure
- [ ] Check JSON includes all necessary fields for rendering
- [ ] Console: `await heatDataManager.storeHeatData(55, {...})`
- [ ] Console: `await heatDataManager.getHeat(55, 1)` - verify retrieval
- [ ] Check IndexedDB in DevTools → Application → IndexedDB

---

### Phase 2: Shared Components (6-8 hours)

**Goal:** Build reusable components used by all heat types

#### Tasks

1. **Heat Header Component** (`app/javascript/components/shared/heat-header.js`)
   ```javascript
   class HeatHeader extends HTMLElement {
     connectedCallback() {
       const data = JSON.parse(this.getAttribute('data'));
       this.render(data);
     }

     render(heat) {
       this.innerHTML = `
         <div class="flex justify-between items-center mb-4">
           <div>
             <h2 class="text-2xl font-bold">Heat ${heat.number}</h2>
             <p class="text-gray-600">${heat.category} - ${heat.dance}</p>
           </div>
           ${heat.ballroom ? `<span class="text-xl">${heat.ballroom}</span>` : ''}
         </div>
       `;
     }
   }

   customElements.define('heat-header', HeatHeader);
   ```

2. **Info Box Component** (`app/javascript/components/shared/heat-info-box.js`)
   - Render keyboard shortcuts
   - Show scoring instructions
   - Collapsible/expandable

3. **Navigation Footer Component** (`app/javascript/components/shared/heat-navigation.js`)
   - Previous/Next buttons
   - Heat number selector
   - Listen for keyboard events (ArrowLeft/ArrowRight)
   - Update URL without page reload

**Deliverables:**
- ✅ Three shared components built and registered
- ✅ Each component accepts data via attribute
- ✅ Components render correctly in isolation

**Testing:**
- [ ] Create test HTML page with shared components
- [ ] Pass sample data, verify rendering
- [ ] Test keyboard navigation
- [ ] Test prev/next buttons

---

### Phase 3: Heat Type Components (12-16 hours)

**Goal:** Build the four main heat type renderers

#### Task Order (simplest to most complex)

1. **Cards Heat Component** (`app/javascript/components/heat-types/heat-cards.js`)
   - 46 lines of ERB (simplest)
   - Draggable back numbers
   - Score zones
   - Drag-and-drop handlers

2. **Solo Heat Component** (`app/javascript/components/heat-types/heat-solo.js`)
   - 103 lines of ERB
   - Lead/follow/instructor display
   - Score inputs (4-part or simple)
   - Comments textarea
   - Formation details

3. **Rank Heat Component** (`app/javascript/components/heat-types/heat-rank.js`)
   - 66 lines of ERB
   - Finals table
   - Ranking inputs
   - Callback checkboxes for semi-finals

4. **Table Heat Component** (`app/javascript/components/heat-types/heat-table.js`)
   - 222 lines of ERB (most complex)
   - Table with multiple couples
   - Radio buttons / score inputs
   - Comments per couple
   - Grouping by dance/studio/category
   - Conditional columns

**Deliverables:**
- ✅ Four heat type components built
- ✅ Each handles score input and submission
- ✅ Each integrates with existing score_controller.js logic

**Testing:**
- [ ] Test each component with representative data
- [ ] Verify scoring works (radio, input, drag-drop)
- [ ] Test edge cases (empty heats, single couple, etc.)

---

### Phase 4: Orchestrator Component (4-6 hours)

**Goal:** Build top-level component that coordinates everything

#### Tasks

1. **Heat Page Component** (`app/javascript/components/heat-page.js`)
   ```javascript
   class HeatPage extends HTMLElement {
     static get observedAttributes() {
       return ['heat-number', 'judge-id'];
     }

     async connectedCallback() {
       this.judgeId = parseInt(this.getAttribute('judge-id'));
       this.heatNumber = parseFloat(this.getAttribute('heat-number'));

       await this.loadData();
       this.render();
       this.attachEventListeners();
     }

     async loadData() {
       // Try to get from IndexedDB first
       let data = await window.heatDataManager.getHeatData(this.judgeId);

       // If missing or stale, fetch from server
       if (!data || await window.heatDataManager.isStale(this.judgeId)) {
         if (navigator.onLine) {
           await this.fetchFromServer();
           data = await window.heatDataManager.getHeatData(this.judgeId);
         } else {
           console.warn('Offline and no cached data');
           return;
         }
       }

       this.allData = data;
       this.heat = data.heats.find(h => h.number === this.heatNumber);
     }

     async fetchFromServer() {
       const response = await fetch(`/scores/${this.judgeId}/heats.json`);
       const data = await response.json();
       await window.heatDataManager.storeHeatData(this.judgeId, data);
     }

     render() {
       if (!this.heat) {
         this.innerHTML = '<p>Heat not found</p>';
         return;
       }

       // Determine which heat type to render
       const heatType = this.determineHeatType();

       this.innerHTML = `
         <div class="flex flex-col h-screen max-h-screen w-full">
           <heat-header data='${JSON.stringify(this.heat)}'></heat-header>
           <heat-info-box data='${JSON.stringify(this.getInfoBoxData())}'></heat-info-box>

           <div class="h-full flex flex-col max-h-[85%]"
                data-controller="score"
                data-heat="${this.heatNumber}">
             ${this.renderHeatType(heatType)}
           </div>

           <heat-navigation
             data='${JSON.stringify(this.getNavigationData())}'
             current-heat="${this.heatNumber}">
           </heat-navigation>
         </div>
       `;
     }

     determineHeatType() {
       if (this.heat.category === 'Solo') return 'solo';
       if (this.heat.final) return 'rank';
       if (this.heat.style === 'cards') return 'cards';
       return 'table';
     }

     renderHeatType(type) {
       const componentMap = {
         solo: 'heat-solo',
         rank: 'heat-rank',
         cards: 'heat-cards',
         table: 'heat-table'
       };

       const component = componentMap[type];
       return `<${component} data='${JSON.stringify(this.heat)}'></${component}>`;
     }

     attachEventListeners() {
       // Listen for URL changes (back/forward buttons)
       window.addEventListener('popstate', () => this.handleUrlChange());

       // Listen for heat navigation events
       this.addEventListener('navigate-to-heat', (e) => {
         this.navigateToHeat(e.detail.heatNumber);
       });
     }

     handleUrlChange() {
       const match = window.location.pathname.match(/\/heat\/(\d+\.?\d*)/);
       if (match) {
         this.setAttribute('heat-number', match[1]);
       }
     }

     navigateToHeat(heatNumber) {
       const url = `/scores/${this.judgeId}/heat/${heatNumber}`;
       window.history.pushState({}, '', url);
       this.setAttribute('heat-number', heatNumber);
     }

     attributeChangedCallback(name, oldValue, newValue) {
       if (oldValue !== newValue && this.isConnected) {
         this.loadData().then(() => this.render());
       }
     }
   }

   customElements.define('heat-page', HeatPage);
   ```

2. **Replace heat.html.erb** (`app/views/scores/heat.html.erb`)

   Replace the entire existing template with just:
   ```erb
   <heat-page
     heat-number="<%= @number %>"
     judge-id="<%= @judge.id %>">
   </heat-page>
   ```

   Controller logic stays the same - no changes needed to `scores_controller.rb`.

**Deliverables:**
- ✅ Heat page component orchestrates all sub-components
- ✅ URL routing works (heat number in URL)
- ✅ Browser back/forward buttons work
- ✅ Data fetched from server or IndexedDB

**Testing:**
- [ ] Navigate to `/scores/55/heat/1`
- [ ] Verify page renders correctly
- [ ] Click next/prev buttons - URL updates
- [ ] Use browser back button - works correctly
- [ ] Go offline, navigate between heats - works from IndexedDB
- [ ] Go online, refresh data - updates from server

---

### Phase 5: Score Submission Integration (4-6 hours)

**Goal:** Connect components to existing scoring infrastructure

#### Tasks

1. **Update Score Controller** (`app/javascript/controllers/score_controller.js`)
   - Keep existing `post()` method
   - Keep existing keyboard handlers
   - Add method to update IndexedDB after successful submission
   - Emit events that components can listen to

2. **Add Score Event Handling to Components**
   - Each heat type component listens for score changes
   - Update local state when score submitted
   - Show pending/confirmed visual feedback
   - Handle offline queueing (reuse existing IndexedDB queue)

3. **Integrate with Existing Batch Endpoint**
   - Reuse `/scores/:judge/batch` endpoint from service worker implementation
   - Reuse `sync_manager.js` for batch submission
   - Add UI for manual sync if needed

**Deliverables:**
- ✅ Score submission works online
- ✅ Scores queue offline
- ✅ Visual feedback for pending vs confirmed scores
- ✅ Integration with existing backend

**Testing:**
- [ ] Submit score while online - saves immediately
- [ ] Submit score while offline - queues to IndexedDB
- [ ] Go online - queued scores sync automatically
- [ ] Verify no duplicate submissions

---

### Phase 6: Testing & Polish (6-8 hours)

**Goal:** Comprehensive testing and refinement

#### Tasks

1. **Browser Compatibility Testing**
   - Chrome 80+ (ES2020 support)
   - Firefox 74+
   - Safari 13.1+
   - Test on tablets (iPads)

2. **Functionality Testing**
   - Test all heat types with real data
   - Test all scoring methods (radio, input, drag-drop)
   - Test keyboard shortcuts
   - Test navigation (prev/next, direct heat jump)
   - Test with 251 heats
   - Test with different event settings

3. **Performance Testing**
   - Measure initial JSON download size
   - Measure time to first render
   - Test with slow 3G connection
   - Verify smooth scrolling/animations

4. **Edge Cases**
   - Empty heats
   - Very large heats (50+ couples)
   - Missing data
   - Invalid heat numbers
   - Session timeout

5. **Polish**
   - Loading states while fetching data
   - Error messages for failures
   - Smooth transitions between heats
   - Visual feedback for all interactions

**Deliverables:**
- ✅ All tests passing
- ✅ Performance acceptable
- ✅ Edge cases handled
- ✅ UI polish complete

---

## Data Model

### JSON Structure

```json
{
  "judge_id": 55,
  "judge_name": "Jane Smith",
  "event": {
    "name": "2025 Raleigh Showcase",
    "settings": {
      "open_scoring": "#",
      "closed_scoring": "#",
      "solo_scoring": "4",
      "judge_comments": true,
      "column_order": 1,
      "heat_range_cat": 1,
      "assign_judges": 0,
      "track_ages": true
    }
  },
  "heats": [
    {
      "number": 1,
      "category": "Open",
      "dance": "Waltz",
      "ballroom": null,
      "final": false,
      "callbacks": 6,
      "style": "radio",
      "slot": null,
      "subjects": [
        {
          "heat_id": 1593,
          "back_number": "101",
          "lead": {
            "id": 245,
            "name": "John Doe",
            "studio": "Smooth Moves"
          },
          "follow": {
            "id": 246,
            "name": "Jane Doe",
            "studio": "Smooth Moves"
          },
          "instructor": {
            "id": 12,
            "name": "Pro Smith"
          },
          "age": "Adult",
          "level": "Bronze",
          "pro": false,
          "score": {
            "id": 9876,
            "value": "1",
            "good": null,
            "bad": null,
            "comments": ""
          }
        }
      ]
    },
    {
      "number": 2,
      "category": "Solo",
      "dance": "Waltz",
      "subjects": [
        {
          "heat_id": 1594,
          "back_number": "102",
          "lead": {...},
          "follow": {...},
          "song": {
            "title": "Moon River",
            "artist": "Andy Williams"
          },
          "formations": [
            {
              "person": {"id": 247, "name": "Extra Dancer"},
              "on_floor": true
            }
          ],
          "score": {
            "value": "{\"technique\":\"8\",\"musicality\":\"9\",\"performance\":\"8\",\"choreography\":\"7\"}",
            "comments": "Great performance"
          }
        }
      ]
    }
  ]
}
```

### IndexedDB Schema

**Database:** `showcase_heats`

**Object Store:** `heats`
- **Key Path:** `judge_id`
- **Indexes:** `timestamp`

**Record Structure:**
```javascript
{
  judge_id: 55,
  data: { /* full JSON from server */ },
  timestamp: 1736123456789
}
```

**Database:** `showcase_offline` (reuse from service worker implementation)

**Object Store:** `pending_scores`
- **Key Path:** `id`
- **Indexes:** `judge_id`, `timestamp`

---

## Files to Retire

### After SPA Implementation is Stable

#### ERB Templates (can be deleted)
```
app/views/scores/
├── _heat_header.html.erb       # → components/shared/heat-header.js
├── _info_box.html.erb           # → components/shared/heat-info-box.js
├── _navigation_footer.html.erb  # → components/shared/heat-navigation.js
├── _solo_heat.html.erb          # → components/heat-types/heat-solo.js
├── _rank_heat.html.erb          # → components/heat-types/heat-rank.js
├── _table_heat.html.erb         # → components/heat-types/heat-table.js
├── _cards_heat.html.erb         # → components/heat-types/heat-cards.js
└── heat.html.erb                # → components/heat-page.js
```

**Total:** 8 ERB files retired

#### Stimulus Controllers

**Keep and refactor:**
- `score_controller.js` - **Still needed**, but refactored:
  - Keep: POST request logic for score submission
  - Keep: Keyboard event handlers (arrows, tab, escape, etc.)
  - Keep: Drag-and-drop logic for cards heat
  - **Remove**: DOM manipulation specific to ERB templates
  - **Change**: Components will handle their own rendering
  - **Change**: Controller becomes a helper for score submission, not rendering

**How score_controller.js will be used:**
- Web components will instantiate the controller or call its methods
- Example: `heat-cards.js` will use drag-and-drop methods from score_controller
- Example: `heat-page.js` will use keyboard handlers from score_controller
- The controller becomes more like a library of scoring utilities rather than a traditional Stimulus controller

**No files to retire from main branch:**
- All service worker related files (`service-worker.js`, `service_worker_controller.js`, `offline_controller.js`, etc.) are only on the `offline-scoring-service-worker` branch
- `main` branch is clean and only has the ERB templates and `score_controller.js`

### Files to Keep

**Still needed:**
```
app/javascript/helpers/
└── heat_data_manager.js         # NEW - manages heat data in IndexedDB

app/controllers/
└── scores_controller.rb         # Keep - handles both ERB and SPA

config/
└── routes.rb                    # Keep - routes to both versions

app/views/scores/
├── heatlist.html.erb            # Keep - not converted to SPA yet
├── index.html.erb               # Keep - not converted to SPA yet
└── heat_spa.html.erb            # NEW - minimal wrapper for SPA
```

### Deployment Strategy

Simple approach: Deploy and test, rollback if needed.

**Pre-deployment checklist:**
- [ ] All heat types work correctly (solo, rank, table, cards)
- [ ] All scoring methods work (radio, input, drag-drop, comments)
- [ ] Offline functionality verified in development
- [ ] Performance acceptable (< 3s initial load on dev data)
- [ ] Browser compatibility verified (Chrome, Firefox, Safari)
- [ ] Test with production data clone

**Deployment:**
1. Deploy to production
2. Test immediately with a real judge account
3. If issues found, rollback via git revert
4. If successful, monitor first event closely

**Rollback plan:**
- Git revert to previous commit
- Redeploy
- ERB templates still in git history if needed

---

## Testing Strategy

### Unit Testing (JavaScript)

**Components to test:**
- Each heat type component in isolation
- Shared components (header, navigation, info-box)
- Heat data manager (IndexedDB operations)
- Heat page orchestrator (component selection logic)

**Test approach:**
- Use Jest or similar framework
- Mock IndexedDB with fake-indexeddb
- Test with sample JSON data
- Verify correct HTML output
- Test event handling (clicks, keyboard)

### Integration Testing

**Scenarios:**
1. **First visit (online)**
   - JSON fetched from server
   - Stored in IndexedDB
   - Heat rendered correctly

2. **Subsequent visit (online, cached)**
   - Data loaded from IndexedDB
   - No network request
   - Heat rendered correctly

3. **Visit after data stale**
   - Fresh fetch from server
   - IndexedDB updated
   - Heat rendered with new data

4. **Offline navigation**
   - Load heat from IndexedDB
   - Navigate between heats
   - No network errors

5. **Score submission (online)**
   - POST to server succeeds
   - UI updates immediately
   - IndexedDB updated

6. **Score submission (offline)**
   - Score queued in IndexedDB
   - UI shows pending state
   - Sync when online

### Manual Testing Protocol

**Setup:**
1. Start Rails server
2. Open DevTools (Network, Application tabs)
3. Navigate to `/scores/55/heat/1?spa=1`

**Test Cases:**

**TC1: Initial Load**
1. Clear IndexedDB
2. Visit heat page
3. ✓ Verify JSON fetched from `/scores/55/heats.json`
4. ✓ Verify data stored in IndexedDB
5. ✓ Verify heat renders correctly

**TC2: Navigation**
1. Click "Next" button
2. ✓ URL changes to `/scores/55/heat/2`
3. ✓ Heat 2 renders
4. Click browser back button
5. ✓ Heat 1 renders

**TC3: Offline Mode**
1. Go offline (Network → Offline)
2. Navigate to heat 5
3. ✓ Heat loads from IndexedDB
4. ✓ No network errors
5. Navigate to heat 10
6. ✓ Heat loads from IndexedDB

**TC4: Score Submission (Online)**
1. Go online
2. Select a score on heat 1
3. ✓ POST request succeeds
4. ✓ UI updates immediately
5. Refresh page
6. ✓ Score persists

**TC5: Score Submission (Offline)**
1. Go offline
2. Select a score on heat 2
3. ✓ No network request
4. ✓ UI shows pending indicator
5. Go online
6. ✓ Score syncs automatically
7. ✓ UI updates to confirmed

**TC6: Data Refresh**
1. With data in IndexedDB
2. Add `?refresh=1` to URL
3. ✓ Fresh data fetched
4. ✓ IndexedDB updated
5. ✓ Heat re-renders with new data

**TC7: All Heat Types**
1. Test solo heat
2. Test rank heat (finals)
3. Test table heat (callbacks)
4. Test cards heat (drag-drop)
5. ✓ All render correctly
6. ✓ Scoring works in each

### Performance Testing

**Metrics to measure:**
- JSON download time (target: < 2s for 251 heats)
- JSON size (estimate: ~500KB-1MB compressed)
- Time to first render (target: < 1s)
- Time to render complex heat (target: < 500ms)
- Memory usage (target: < 50MB)
- Navigation between heats (target: < 100ms)

**Tools:**
- Chrome DevTools Performance tab
- Network tab (with throttling)
- Memory profiler

---

## Future Phases

### Phase 7: DJ Pages (Estimated 8-12 hours)

DJ pages are simpler than judge pages:
- No scoring logic
- Just display current heat, upcoming heats
- Possibly music controls

**Components needed:**
- `dj-current-heat.js` - Show what's on floor now
- `dj-upcoming.js` - Show next 3-5 heats
- `dj-music-player.js` - If managing music playback

**Approach:**
- Reuse `heat_data_manager.js` for heat data
- Much simpler than judge components
- Likely only 2-3 components total

### Phase 8: Emcee Pages (Estimated 8-12 hours)

Similar to DJ pages:
- Display current heat info
- Show who's on floor
- Announcements

**Components needed:**
- `emcee-current-heat.js` - Detailed heat info for announcing
- `emcee-participants.js` - Names to announce

**Approach:**
- Reuse heat data infrastructure
- Focus on readable display for announcing
- Large text, clear formatting

### Phase 9: Enhanced Features (Future)

Once core SPA is stable:
- Real-time updates via WebSocket (ActionCable)
- Push notifications for heat changes
- PWA features (install prompt, icons)
- Advanced offline capabilities (edit heat list offline)
- Analytics (track scoring patterns, time per heat)

---

## Estimated Effort Summary

| Phase | Description | Hours |
|-------|-------------|-------|
| 1 | Infrastructure (JSON API, IndexedDB) | 4-6 |
| 2 | Shared Components | 6-8 |
| 3 | Heat Type Components | 12-16 |
| 4 | Orchestrator Component | 4-6 |
| 5 | Score Submission Integration | 4-6 |
| 6 | Testing & Polish | 6-8 |
| **Total** | **Judge Scoring SPA** | **36-50 hours** |

### Future Phases
| Phase | Description | Hours |
|-------|-------------|-------|
| 7 | DJ Pages | 8-12 |
| 8 | Emcee Pages | 8-12 |
| **Total** | **All Event Pages** | **52-74 hours** |

---

## Success Criteria

### Functional Requirements
- [ ] All heat types render correctly (solo, rank, table, cards)
- [ ] All scoring methods work (radio, input, drag-drop, comments)
- [ ] Navigation works (prev/next, heat selector, back button)
- [ ] Keyboard shortcuts work
- [ ] Scores submit successfully online
- [ ] Scores queue when offline
- [ ] Data syncs when returning online
- [ ] Works on all target browsers (Chrome 80+, Firefox 74+, Safari 13.1+)

### Performance Requirements
- [ ] Initial JSON download < 2 seconds (on 3G)
- [ ] Time to first render < 1 second
- [ ] Heat navigation < 100ms
- [ ] Heat rendering < 500ms
- [ ] Memory usage < 50MB
- [ ] Smooth animations (60fps)

### Quality Requirements
- [ ] No console errors
- [ ] Proper error handling (network failures, missing data)
- [ ] Loading states for all async operations
- [ ] Visual feedback for all user actions
- [ ] Accessible (keyboard navigation, screen readers)
- [ ] Mobile-friendly (works on tablets)

### Maintainability Requirements
- [ ] Components are modular and reusable
- [ ] Code is well-commented
- [ ] Consistent naming conventions
- [ ] Clear separation of concerns
- [ ] Easy to add new heat types if needed

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| JSON too large | Low | Medium | Compress, paginate if needed, measure early |
| Complex heat logic hard to port | Medium | High | Start with simplest (cards), build up gradually |
| Browser compatibility issues | Low | Medium | Test early on target browsers, use polyfills |
| Performance on older devices | Medium | Medium | Test on older iPads, optimize rendering |
| Feature parity with ERB | Medium | High | Careful testing, keep ERB as fallback initially |
| Data sync conflicts | Low | Medium | Reuse existing idempotent batch endpoint |

---

## Next Steps

1. Review this plan with stakeholders
2. Create feature branch: `git checkout -b spa-scoring`
3. Begin Phase 1 (Infrastructure)
4. Test JSON endpoint with production data
5. Validate IndexedDB storage
6. Proceed to Phase 2

---

## Notes

### Why Not a Framework?

We considered React, Vue, or Svelte but chose Custom Elements because:
- No build step needed (works with importmap)
- No framework lock-in
- Native browser API
- Smaller footprint
- Works with existing Stimulus setup
- Easier for Rails developers to understand

### Why Keep ERB for Non-Scoring Pages?

Converting the entire app to SPA is unnecessary:
- Reports, admin pages don't need offline access
- ERB is simpler for pages that don't change often
- Reduces migration scope and risk
- Can always convert later if needed

### Why IndexedDB Instead of Service Worker Cache?

IndexedDB provides:
- Structured data storage (not just HTML)
- Easy querying (find heat by number)
- Predictable state (no cache version conflicts)
- Better debugging experience
- Reusable for other features

### Why Keep Stimulus score_controller.js?

The score controller handles:
- Drag-and-drop physics
- Keyboard event handling
- Score POST requests
- Integration with existing backend

Rather than rewrite this proven code, we integrate it with the new components. The controller becomes lighter (less DOM manipulation) but keeps its core responsibilities.
