# Ruby2JS Shared Logic Architecture

## Status: Stage 1 Complete — Ready for Implementation

Ruby2JS now has the capabilities needed to eliminate duplicate view logic in the offline scoring SPA. The original plan proposed a custom annotation DSL, but the Rails model filter may make that unnecessary.

### Context

The showcase application maintainer is also the Ruby2JS maintainer. Ruby2JS is not a risky dependency — it's a tested, documented project with community support. Changes needed to support showcase can be made directly.

### What Ruby2JS Now Provides (December 2025)

1. **ERB filter** — transpiles ERB templates to JavaScript render functions
2. **Rails model filter** — understands `has_many`, `belongs_to`, `validates`, etc.
3. **Rails controller/routes/helpers filters** — complete MVC transpilation
4. **Self-hosting** — Ruby2JS runs in the browser
5. **Proven demo** — "Ruby2JS on Rails" blog tutorial running entirely in browser

## Problem Statement

The offline-first scoring SPA requires:

1. **Snapshot data** from server before going offline
2. **Render views** from that snapshot while offline
3. **Send updates** when connectivity resumes

Currently, view rendering is duplicated:

- **Server:** ERB templates render with ActiveRecord objects
- **Client:** Hand-written Web Components render with hydrated JSON

When view logic changes, both implementations must be updated. This creates maintenance burden and risk of drift.

## Current Architecture

```
Server (Ruby)                          Client (JavaScript)
─────────────────                      ────────────────────
ScoresController#heats_data            heat_hydrator.js
  - Manual hash building (~200 lines)    - buildLookupTables()
  - Compute dance_string                 - hydrateHeat()
  - Compute scoring_type                 - buildHeatTemplateData()
  - Compute category_scoring_category_id   - Category scoring expansion
                                           - Final/callbacks flags
                                           - Ballroom grouping

ScoresController#heat
  - Category scoring expansion         (duplicated in JS)
  - Subject sorting                    (duplicated in JS)
  - Ballroom grouping                  (duplicated in JS)

Implicit JSON contract between server serialization and client expectations
```

## Data Flow (Current vs Target)

The offline scoring flow has four stages:

```
Serialization → Storage → Hydration → Rendering
    (1)           (2)        (3)         (4)
```

### Current Implementation

| Stage | Server | Client | Duplication? |
|-------|--------|--------|--------------|
| 1. Serialization | `heats_data` builds JSON | — | No |
| 2. Storage | — | `HeatDataManager` → IndexedDB | No |
| 3. Hydration | — | `heat_hydrator.js` rebuilds objects | Implicit contract |
| 4. Rendering | ERB templates | Web Components | **YES — duplicated** |

### Target Implementation

| Stage | Implementation | Source of Truth |
|-------|----------------|-----------------|
| 1. Serialization | Keep or derive from model definitions | Model definitions |
| 2. Storage | Keep `HeatDataManager` or migrate to Dexie | — |
| 3. Hydration | Transpiled from model definitions | Model definitions |
| 4. Rendering | Transpiled ERB → JavaScript | **ERB templates** |

## Proposed Architecture

A proper subset of the showcase application (routes, models, views, controllers) gets transpiled into a client-side SPA backed by Dexie/IndexedDB.

```
Server (Rails)                       Client (Transpiled SPA)
─────────────────                    ───────────────────────
Routes (subset)          ──────►     Routes (transpiled)
Models (subset)          ──────►     Models (Dexie-backed)
Views (scoring ERB)      ──────►     Views (render functions)
Controllers (subset)     ──────►     Controllers (transpiled)
                                            │
                                            ▼
                                     Navigation + Sync Layer
                                     ────────────────────────
                                     On each navigation:
                                       1. Attempt server request
                                       2. Upload pending changes (batch)
                                       3. Download updates (batch)
                                       4. Fall back to IndexedDB if offline
```

### Sync Behavior

On every navigation, the client attempts to sync with the server:
- **Upload:** Batch of pending score changes queued while offline
- **Download:** Latest data updates from server
- **Fallback:** If offline, proceed with local IndexedDB data

### Turbo Integration (Recommended)

Ruby2JS can build on Turbo rather than replacing it. Key insight: `Turbo.renderStreamMessage()` processes Turbo Stream HTML regardless of source — server response or client-side generated.

```
Transpiled ERB → Generate Turbo Stream HTML → Turbo.renderStreamMessage() → DOM update
```

**How it works:**

| Component | Role |
|-----------|------|
| **Turbo Drive** | Navigation (intercepted to render locally from Dexie when offline) |
| **Turbo Streams** | DOM updates (generated client-side by transpiled ERB) |
| **Stimulus** | Interactivity (unchanged — existing controllers work as-is) |
| **Turbo events** | Sync hooks (`turbo:before-visit` for upload/download batch) |

**Benefits:**
- Existing Stimulus controllers work unchanged (they already use Turbo events/APIs)
- No parallel navigation system to build
- `turbo:before-visit`, `turbo:load` available for sync hooks
- Turbo Frames/Streams available for progressive enhancement

**Sync on navigation:**
```javascript
document.addEventListener('turbo:before-visit', async (event) => {
  // 1. Upload pending changes
  await uploadDirtyScores();
  // 2. Download updates (or proceed offline)
  await downloadUpdates().catch(() => {/* offline fallback */});
});
```

This approach integrates with the existing Hotwire stack rather than replacing it.

### Stimulus Compatibility

Analyzed scoring view controllers for Turbo dependencies:

| Controller | Turbo Usage | Offline SPA Impact |
|------------|-------------|-------------------|
| `score_controller.js` | `turbo:before-visit` event | Works unchanged |
| `drop_controller.js` | `Turbo.renderStreamMessage()` | Can generate Turbo Stream locally |
| `open_feedback_controller.js` | None | Works unchanged |
| `info_box_controller.js` | None | Works unchanged |

**Conclusion:** Existing Stimulus controllers work with the Turbo integration approach. The two controllers using `Turbo.renderStreamMessage()` (`drop_controller.js`, `live_scores_controller.js`) can receive locally-generated Turbo Stream HTML instead of server responses.

**Key insight:** The Rails model filter already knows object shapes from `has_many`, `belongs_to`, etc. A custom annotation DSL may be unnecessary — model definitions can serve as the source of truth for hydration.

## Model Annotation Design (Original Plan — Likely Unnecessary)

> **Note:** This section documents the originally proposed annotation DSL. Given that the Rails model filter already understands model relationships, this custom DSL may be unnecessary. Preserved for reference.

### Basic Structure

```ruby
# app/models/heat.rb
class Heat < ApplicationRecord
  belongs_to :dance
  belongs_to :entry
  has_one :solo
  has_many :scores

  spa_serialize do
    # Simple attributes from schema
    attributes :id, :number, :category, :ballroom

    # Computed: existing method, result serialized
    # Server calls method, client receives value
    computed :pro

    # Computed with context: method needs external data
    # Server computes with context, client receives pre-computed string
    computed :subject_lvlcat, context: [:track_ages], precompute: true

    # Computed with block: logic converted to JS via Ruby2JS
    # Both server and client execute the same logic
    computed :display_category do |heat|
      heat.pro ? 'Professional' : "#{heat.level.initials} - #{heat.age.category}"
    end

    # References for eager loading and hydration
    references :dance, :entry, :solo
  end
end
```

### Three Modes for Computed Fields

1. **`computed :method_name`**
   - Server calls existing method, serializes result
   - Client receives value, no computation needed
   - Example: `computed :pro` → server sends `true`/`false`

2. **`computed :method_name, precompute: true`**
   - Server computes once with context, sends as value
   - Client has no logic, just uses pre-computed value
   - Good for logic depending on `Event.current` or other server state
   - Example: `computed :subject_lvlcat, context: [:track_ages], precompute: true`

3. **`computed :name do |model| ... end`**
   - Block source is extracted via Ruby2JS introspection
   - Ruby2JS converts block to JavaScript
   - **Both server and client execute identical logic**
   - Useful when client might need to re-execute (e.g., after local updates)

### Ruby2JS Block Introspection

Ruby2JS can accept a Proc and use `source_location` to read the original source:

```ruby
# Ruby2JS.convert accepts a Proc directly
js_code = Ruby2JS.convert(proc { |x| x * 2 })
# => "(x) => x * 2"
```

This means computed blocks are written once in Ruby and automatically converted:

```ruby
computed :display_category do |heat|
  heat.pro ? 'Professional' : "#{heat.level.initials} - #{heat.age.category}"
end
```

Ruby2JS reads this block's source and generates:

```javascript
displayCategory(heat) {
  return heat.pro ? 'Professional' : `${heat.level.initials} - ${heat.age.category}`;
}
```

### Full Model Examples

```ruby
# app/models/heat.rb
class Heat < ApplicationRecord
  belongs_to :dance
  belongs_to :entry
  has_one :solo
  has_many :scores

  spa_serialize do
    attributes :id, :number, :category, :ballroom

    # Pre-computed on server (depends on heats_same_number context)
    computed :dance_string, precompute: true
    computed :scoring_type, precompute: true
    computed :category_scoring_category_id, precompute: true

    references :dance, :entry, :solo
  end
end

# app/models/entry.rb
class Entry < ApplicationRecord
  belongs_to :lead, class_name: 'Person'
  belongs_to :follow, class_name: 'Person'
  belongs_to :instructor, class_name: 'Person', optional: true
  belongs_to :age
  belongs_to :level

  spa_serialize do
    attributes :id, :lead_id, :follow_id, :instructor_id,
               :studio_id, :age_id, :level_id

    computed :pro
    computed :level_name
    computed :subject_lvlcat, context: [:track_ages], precompute: true
    computed :subject_category, context: [:track_ages], precompute: true

    references :lead, :follow, :instructor, :age, :level
  end
end

# app/models/person.rb
class Person < ApplicationRecord
  belongs_to :studio

  spa_serialize do
    attributes :id, :name, :back, :type
    computed :display_name
    references :studio
  end
end

# app/models/studio.rb
class Studio < ApplicationRecord
  spa_serialize do
    attributes :id, :name
  end
end
```

## Generated Code

### Ruby Serializer

```ruby
# lib/generated/spa_serializers.rb (generated, do not edit)
module SpaSerializers
  module HeatSerializer
    def self.serialize(heat, context = {})
      {
        id: heat.id,
        number: heat.number,
        category: heat.category,
        ballroom: heat.ballroom,
        dance_id: heat.dance_id,
        entry_id: heat.entry_id,
        solo_id: heat.solo&.id,
        dance_string: context[:dance_strings]&.[](heat.id),
        scoring_type: context[:scoring_types]&.[](heat.id),
        category_scoring_category_id: context[:category_ids]&.[](heat.id)
      }
    end

    def self.includes_for_preload
      { dance: [], entry: [:lead, :follow, :instructor, :age, :level], solo: [] }
    end
  end

  module EntrySerializer
    def self.serialize(entry, context = {})
      {
        id: entry.id,
        lead_id: entry.lead_id,
        follow_id: entry.follow_id,
        instructor_id: entry.instructor_id,
        studio_id: entry.studio_id,
        age_id: entry.age_id,
        level_id: entry.level_id,
        pro: entry.pro,
        level_name: entry.level_name,
        subject_lvlcat: entry.subject_lvlcat(context[:track_ages]),
        subject_category: entry.subject_category(context[:track_ages])
      }
    end

    def self.includes_for_preload
      { lead: :studio, follow: :studio, instructor: :studio, age: [], level: [] }
    end
  end
  # ... more serializers
end
```

### JavaScript Hydrator

```javascript
// app/javascript/generated/spa_hydrators.js (generated, do not edit)

export function hydrateHeat(heat, lookups) {
  return {
    ...heat,
    dance: lookups.dances[heat.dance_id],
    entry: heat.entry_id ? hydrateEntry(lookups.entries[heat.entry_id], lookups) : null,
    solo: heat.solo_id ? lookups.solos[heat.solo_id] : null
  };
}

export function hydrateEntry(entry, lookups) {
  if (!entry) return null;
  return {
    ...entry,
    lead: hydratePerson(lookups.people[entry.lead_id], lookups),
    follow: hydratePerson(lookups.people[entry.follow_id], lookups),
    instructor: entry.instructor_id ? hydratePerson(lookups.people[entry.instructor_id], lookups) : null,
    age: lookups.ages[entry.age_id],
    level: lookups.levels[entry.level_id]
  };
}

export function hydratePerson(person, lookups) {
  if (!person) return null;
  return {
    ...person,
    studio: lookups.studios[person.studio_id]
  };
}
```

### TypeScript Definitions (Optional)

```typescript
// app/javascript/generated/spa_types.d.ts (generated, do not edit)

export interface HeatData {
  id: number;
  number: number;
  category: 'Open' | 'Closed' | 'Solo' | 'Multi';
  ballroom: number | null;
  dance_id: number;
  entry_id: number | null;
  solo_id: number | null;
  dance_string: string;
  scoring_type: string;
  category_scoring_category_id: number | null;
}

export interface HydratedHeat extends HeatData {
  dance: DanceData;
  entry: HydratedEntry | null;
  solo: SoloData | null;
}

// ... more interfaces
```

## Shared Logic via Ruby2JS

For complex logic that must run on both server and client (like category scoring expansion), use computed blocks:

```ruby
# app/models/concerns/spa_shared_logic.rb
module SpaSharedLogic
  extend ActiveSupport::Concern

  class_methods do
    # Shared logic: category scoring expansion
    # This block is converted to JS and used on both sides
    def expand_category_scoring
      proc do |subjects, category_scoring_enabled, category_scores|
        return subjects unless category_scoring_enabled

        expanded = []
        subjects.each do |subject|
          students = []
          students << {student: subject[:lead], role: 'lead'} if subject[:lead]&.[](:type) == 'Student'
          students << {student: subject[:follow], role: 'follow'} if subject[:follow]&.[](:type) == 'Student'

          if students.length == 2
            students.each do |student_info|
              expanded << subject.merge(
                subject: student_info[:student],
                student_role: student_info[:role],
                scores: category_scores[student_info[:student][:id]] || []
              )
            end
          elsif students.length == 1
            expanded << subject.merge(
              subject: students[0][:student],
              student_role: students[0][:role],
              scores: category_scores[students[0][:student][:id]] || []
            )
          else
            expanded << subject
          end
        end
        expanded
      end
    end
  end
end
```

The generator extracts this proc and:
1. Makes it callable from Ruby: `SpaSharedLogic.expand_category_scoring.call(subjects, enabled, scores)`
2. Converts to JavaScript via Ruby2JS: `expandCategoryScoring(subjects, enabled, scores)`

## Implementation Stages

### Stage 1: Ruby2JS Modernization — ✅ COMPLETE

**Status: Complete and exceeded original scope** (December 2025)

Ruby2JS has been substantially modernized with Prism support, self-hosting, and full Rails filter suite.

#### What Was Built

| Task | Status | Details |
|------|--------|---------|
| Prism support | ✅ Complete | Full `PrismWalker` with 12 visitor modules |
| ERB filter | ✅ Complete | 234-line filter in `lib/ruby2js/filter/erb.rb` |
| Rails filters | ✅ Complete | Model, Controller, Routes, Schema, Helpers, Seeds, Logger |
| Self-hosting | ✅ Complete | Ruby2JS transpiles itself to JavaScript |
| Online demo | ✅ Updated | Self-host option added alongside Opal |

#### Rails Filters Implemented

| Filter | Lines | Transforms |
|--------|-------|------------|
| `rails/model.rb` | 686 | `has_many`, `belongs_to`, `validates`, callbacks, STI, scopes |
| `rails/controller.rb` | 758 | `before_action`, `params`, `render`, `redirect_to`, filter chains |
| `rails/helpers.rb` | 589 | Form helpers, `link_to`, `truncate`, path helpers |
| `rails/routes.rb` | 848 | `resources`, `root`, constraints, URL generation |
| `rails/schema.rb` | 474 | `create_table`, column definitions |
| `rails/seeds.rb` | 187 | Module-based seeds with auto-import |
| `rails/logger.rb` | 46 | `Rails.logger` → `console.*` |

#### Self-Hosting Infrastructure

Ruby2JS can now run entirely in JavaScript:
- **CLI** (`lib/ruby2js/selfhost/cli.rb`) — 463 lines
- **Runtime** (`lib/ruby2js/selfhost/runtime.rb`) — Parser-compatible location classes
- **Bundler** (`lib/ruby2js/selfhost/bundle.rb`) — Packages for browser
- **Prism browser** (`lib/ruby2js/selfhost/prism_browser.rb`) — WASI polyfill

Self-host filters transform Ruby2JS's own code:
- `selfhost/core.rb` — Dynamic super handling
- `selfhost/walker.rb` — PrismWalker API transforms
- `selfhost/filter.rb` — Filter module patterns
- `selfhost/converter.rb` — Converter patterns

#### Enumerable Methods ✅

These methods are now implemented in `filter/functions.rb`:

| Method | Implementation |
|--------|----------------|
| `group_by` | ES2024 `Object.groupBy` or `reduce` fallback |
| `sort_by` | ES2023 `toSorted` or `slice().sort` fallback |
| `max_by` | `reduce` with comparison |
| `min_by` | `reduce` with comparison |

**Outcome:** Ruby2JS is production-ready with comprehensive Rails support.

### Stage 2: ERB Transpilation for Views

**Goal:** Eliminate view duplication by transpiling ERB templates to JavaScript.

**Prerequisites (Ruby2JS):**
- Add `dom_id` to Rails helpers filter (small)
- Expose `pluralize` as view helper (small)

**Approach:**
1. Transpile one scoring partial (e.g., `_heat_table.html.erb`) as proof of concept
2. Verify transpiled output renders identically to Web Component
3. Transpile remaining scoring views
4. Replace Web Components with transpiled render functions

**What this solves:**
- View logic exists in one place (ERB templates)
- No manual sync between ERB and JavaScript
- `compare-erb-js` tests become unnecessary — nothing to compare

**What this doesn't change:**
- Data flow (serialization → storage → hydration) stays the same initially
- `HeatDataManager` and IndexedDB usage unchanged
- Score submission and ActionCable integration unchanged

### Stage 3: Hydration from Model Definitions

**Goal:** Derive hydration logic from model definitions instead of hand-written `heat_hydrator.js`.

**Approach:**
1. Transpile relevant model definitions with Rails model filter
2. Use transpiled models to hydrate JSON from IndexedDB
3. Transpiled views consume hydrated model objects

**Key question:** Does the Rails model filter produce models that:
- Can hydrate from JSON?
- Provide AR-like interface (`heat.entry.lead.name`)?
- Handle relationships correctly?

The ruby2js-on-rails demo uses Dexie which handles this. For showcase, we need to verify the model filter works with the existing `HeatDataManager` approach, or decide to migrate to Dexie.

### Stage 4: Simplify Serialization (Optional)

**Goal:** Derive serialization from model definitions if beneficial.

Once views and hydration are transpiled, evaluate whether `heats_data` serialization can also be derived from model definitions. This may not be necessary — the current serialization works and isn't duplicated.

**Decision point:** If hydration is derived from models, serialization might "just work" as the inverse. Explore after Stages 2-3 are complete.

### Dependencies

```
Stage 1 (Ruby2JS Modernization) ✅ COMPLETE
    │
    ├── Prism migration ✅
    ├── ERB filter ✅
    ├── Rails filters ✅ (7 filters, ~3,600 lines)
    └── Self-hosting ✅
          │
          ▼
Stage 2 (ERB Transpilation for Views)
    │
    └── Transpile scoring ERB → JavaScript render functions
          │
          ▼
Stage 3 (Hydration from Model Definitions)
    │
    └── Transpile models → JavaScript with AR-like interface
          │
          ▼
Stage 4 (Simplify Serialization) — Optional
    │
    └── Evaluate if heats_data can be derived from models
```

Stages are sequential but independently valuable. Stage 2 alone eliminates view duplication.

## What Gets Transpiled vs What Remains Manual

### After Stage 2 (Views)

| Transpiled | Source | Output |
|------------|--------|--------|
| Scoring views | `app/views/scores/_*.html.erb` | JavaScript render functions |

| Manual | Notes |
|--------|-------|
| Hydration | `heat_hydrator.js` — unchanged initially |
| Storage | `HeatDataManager` — unchanged |
| Serialization | `heats_data` — unchanged |
| Score submission | Existing logic — unchanged |
| ActionCable | Existing integration — unchanged |

### After Stage 3 (Models)

| Transpiled | Source | Output |
|------------|--------|--------|
| Scoring views | ERB templates | JavaScript render functions |
| Model hydration | Model definitions | JavaScript models with AR interface |

| Manual | Notes |
|--------|-------|
| Storage | `HeatDataManager` or Dexie — TBD |
| Serialization | `heats_data` — likely unchanged |
| Score submission | Existing logic — unchanged |
| ActionCable | Existing integration — unchanged |

### After Stage 4 (Optional)

| Transpiled | Source | Output |
|------------|--------|--------|
| Scoring views | ERB templates | JavaScript render functions |
| Model hydration | Model definitions | JavaScript models |
| Serialization | Model definitions | Derived from same source as hydration |

| Manual | Notes |
|--------|-------|
| Storage | Data layer implementation |
| Score submission | Business logic |
| ActionCable | Real-time integration |

## Risk Verification (All Verified ✅)

All originally identified risks have been verified as non-blocking through Stage 1 implementation.

### Ruby2JS Output Quality ✅

Tested with actual shared logic patterns. Output is clean, idiomatic JavaScript:

| Ruby Pattern | JavaScript Output | Status |
|--------------|-------------------|--------|
| `subject[:lead]&.[](:type)` | `subject.lead?.["type"]` | ✅ Correct |
| `subject.merge(...)` | `{...subject, ...}` | ✅ Clean spread |
| `students << {...}` | `students.push({...})` | ✅ Correct |
| `category_scores[id] \|\| []` | `category_scores[id] \|\| []` | ✅ Identical |
| String interpolation | Template literals | ✅ Clean |
| `each` with block | `for...of` loop | ✅ Clean |
| `map`, `select`, `find` | `map`, `filter`, `find` | ✅ Correct |
| `case/when` | `switch/case` | ✅ Correct |
| Multi-line nested blocks | Properly structured | ✅ Correct |

### ERB Templates ✅ (New)

The ERB filter (`lib/ruby2js/filter/erb.rb`) handles:
- Buffer detection (`_erbout`, `_buf`)
- Instance variable extraction to function parameters
- Rails helper integration via hooks (`erb_prepend_imports`, `process_erb_block_*`)

### Rails Patterns ✅ (New)

The ruby2js-on-rails demo validates:
- Models with `has_many`, `belongs_to`, `validates`
- Controllers with `before_action`, `params`, `redirect_to`
- Routes with `resources`, nested routes, path helpers
- ERB templates with Rails helpers

### Block Introspection ✅

Ruby2JS can extract and convert blocks defined in model annotations:

| Scenario | Status |
|----------|--------|
| DSL-captured blocks (`computed :name do ... end`) | ✅ Works |
| Multi-line complex blocks | ✅ Works |
| Rake task timing (after `eager_load!`) | ✅ Works |
| Nested structures, case/when | ✅ Works |

### Gap Analysis: Scoring ERB Templates

Analyzed `_table_heat.html.erb`, `_cards_heat.html.erb`, `_rank_heat.html.erb`, `_solo_heat.html.erb`, `_heat_header.html.erb`, `_info_box.html.erb`.

#### Already Implemented ✅

| Feature | Location |
|---------|----------|
| `blank?` | `filter/active_functions` |
| `raw` / `html_safe` | `erb` filter |
| `pluralize` | Implemented (not yet exposed as helper) |
| `group_by`, `sort_by`, `max_by`, `min_by` | `filter/functions` |
| String methods (`gsub`, `split`, `join`, `start_with?`) | `filter/functions` |
| Array/Enumerable (`each`, `map`, `find`, `any?`, `empty?`, `include?`) | `filter/functions` |
| Safe navigation (`&.`) | Core transpiler |
| `respond_to?` | Transpiles to property check |
| `JSON.parse` | Native JS |

#### Gaps to Fill

| Gap | Effort | Notes |
|-----|--------|-------|
| `dom_id` | Small | Add to Rails helpers filter |
| `pluralize` as view helper | Small | Expose existing implementation |

#### Not Gaps (Initially Thought Problematic)

| Pattern | Why It Works |
|---------|--------------|
| `Score.find_by(...)` | Transpiled models + Dexie handle AR-style queries client-side |
| `Event.current` | Can be transpiled model or passed as data |
| ActiveStorage `.url` | Pre-computed server-side, passed as data |

#### Conclusion

**Two small gaps** (`dom_id`, `pluralize` helper exposure). Everything else is implemented or handled by the Rails model filter + Dexie approach.

## Success Criteria

### Stage 2 Complete When:
- Scoring ERB templates transpile to JavaScript render functions
- Transpiled views produce identical output to current Web Components
- Offline scoring works with transpiled views
- Web Component view code can be removed

### Stage 3 Complete When:
- Model definitions transpile to JavaScript with AR-like interface
- Transpiled models hydrate from JSON correctly
- `heat_hydrator.js` can be replaced with transpiled models
- Transpiled views consume transpiled models

### Overall Success:
- View logic changes require editing ERB only (no JS sync)
- `compare-erb-js` tests become unnecessary
- Reduced total JavaScript in SPA (transpiled code replaces hand-written)

## Related Documents

### Showcase Project
- [ERB_TO_JS_TRANSFORMER_ARCHITECTURE.md](ERB_TO_JS_TRANSFORMER_ARCHITECTURE.md) — Modular converter design
- [OFFLINE_SCORING_COMPLETION.md](OFFLINE_SCORING_COMPLETION.md) — Offline scoring implementation plan

### Ruby2JS Resources
- [Ruby2JS](https://www.ruby2js.com/) — Ruby to JavaScript transpiler ([GitHub](https://github.com/ruby2js/ruby2js))
- [Ruby2JS on Rails demo](https://github.com/ruby2js/ruby2js/tree/master/demo/ruby2js-on-rails) — Complete Rails blog running in browser
- [Comparing Approaches: Opal, Ruby WASM, Ruby2JS](https://github.com/ruby2js/ruby2js/blob/master/plans/RUBY_IN_JS_APPROACHES.md)

### Blog Posts (chronological)
- [Offline-First Web Components](https://intertwingly.net/blog/2025/11/07/Offline-First-Web-Components.html) — First offline scoring approach
- [Turbo MVC Offline](https://intertwingly.net/blog/2025/11/20/Turbo-MVC-Offline.html) — Second approach with Turbo navigation
- [ERB to JavaScript Conversion](https://intertwingly.net/blog/2025/11/24/ERB-Stimulus-Offline.html) — ERB template transpilation breakthrough
- [Ruby2JS Prism Support](https://intertwingly.net/blog/2025/11/27/Ruby2JS-Prism-Support.html) — Prism parser integration
- [Three Paths to Ruby2JS in Browser](https://intertwingly.net/blog/2025/11/29/Ruby2JS-Browser-Options.html) — Self-hosting architecture
- [The Ruby2JS Story](https://www.ruby2js.com/blog/2025/12/14/ruby2js-story/) — Project history and revival
- [Ruby2JS on Rails](https://intertwingly.net/blog/2025/12/21/Ruby2JS-on-Rails.html) — Full Rails patterns in browser
