# Ruby2JS Shared Logic Architecture

## Status: Planning

This plan documents an approach to eliminate duplicate business logic between Ruby (server) and JavaScript (client) by:

1. **Model annotations** that declare serialization contracts
2. **Ruby2JS** to transpile shared logic to JavaScript
3. **Code generation** for serializers, hydrators, and type definitions

## Problem Statement

The offline-first scoring SPA requires business logic in both places:

1. **Server (Ruby):** `ScoresController#heat` and `#heats_data` compute derived values, expand category scoring subjects, determine scoring types
2. **Client (JavaScript):** `heat_hydrator.js` duplicates much of this logic to reconstruct the same data structures from normalized JSON

When logic changes (e.g., category scoring expansion for amateur couples), both implementations must be updated in lockstep. This creates maintenance burden and risk of drift.

Additionally, the JSON contract between server and client is implicit—defined only by code on each side. Field additions, renames, or type changes can cause silent failures.

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

## Proposed Architecture

```
Model Annotations (Single Source of Truth)
──────────────────────────────────────────
app/models/heat.rb        → spa_serialize { ... }
app/models/entry.rb       → spa_serialize { ... }
app/models/person.rb      → spa_serialize { ... }
         │
         ▼
    Code Generator
         │
         ├─────────────────────────────────────────────┐
         │                                             │
         ▼                                             ▼
Generated Ruby                         Generated JavaScript
─────────────────                      ────────────────────
lib/generated/spa_serializers.rb       app/javascript/generated/
  - HeatSerializer.serialize()           - spa_hydrators.js
  - EntrySerializer.serialize()          - spa_types.d.ts (optional)
  - includes_for_preload()
```

## Model Annotation Design

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

### Stage 1: Ruby2JS Modernization

**Status: Prism migration complete** (see [ruby2js prism-migration branch](https://github.com/ruby2js/ruby2js))

Ruby2JS now supports Prism via `Prism::Translation::Parser`, which translates Prism's AST into whitequark parser-compatible format. This approach:

- Requires no changes to existing handlers or filters
- Auto-detects Prism on Ruby 3.3+, falls back to parser gem on older Ruby
- All 1302 tests pass with both parsers
- Maintains full backwards compatibility

**Remaining Stage 1 work:**

| Task | Status |
|------|--------|
| Prism support via translation layer | ✅ Complete |
| `group_by`, `sort_by`, `max_by`, `min_by` filters | Pending |
| `erb` filter (extract from `ErbPrismConverter`) | Pending |
| `rails_helpers` filter | Pending |
| `web_components` filter | Pending |
| Online demo update | Pending |

**Online Demo Considerations:**
The ruby2js.com demo currently uses Opal to run Ruby2JS in the browser. Options for Prism compatibility (in priority order):
1. Self-hosting: Ruby2JS transpiles itself to JS, uses `@prism-ruby/prism` npm module directly
2. Replace Opal with ruby.wasm (runs CRuby + native Prism in browser)
3. Continue using Opal with parser gem (no changes needed - translation layer means existing code works)

**Outcome:** Modern Ruby2JS that benefits the broader community and provides foundation for Stage 2.

### Stage 2: Annotation DSL + Generator (Proof of Concept)

Build the `spa_serialize` DSL and generator, validated with one simple model.

Create the `spa_serialize` DSL:

```ruby
# lib/spa_serialize.rb
module SpaSerialize
  extend ActiveSupport::Concern

  class_methods do
    def spa_serialize(&block)
      @spa_config ||= SpaConfig.new(self)
      @spa_config.instance_eval(&block)
    end

    def spa_config
      @spa_config
    end
  end
end

class SpaConfig
  attr_reader :model_class, :attribute_names, :computed_fields, :reference_names

  def initialize(model_class)
    @model_class = model_class
    @attribute_names = []
    @computed_fields = []
    @reference_names = []
  end

  def attributes(*names)
    @attribute_names.concat(names)
  end

  def computed(name, context: [], precompute: false, &block)
    @computed_fields << {
      name: name,
      context: context,
      precompute: precompute,
      block: block
    }
  end

  def references(*names)
    @reference_names.concat(names)
  end
end
```

**Code Generator:**

```ruby
# lib/tasks/spa_generate.rake
namespace :spa do
  desc "Generate serializers and hydrators from model annotations"
  task generate: :environment do
    generator = SpaCodeGenerator.new

    # Find all models with spa_serialize
    Rails.application.eager_load!
    models = ApplicationRecord.descendants.select { |m| m.respond_to?(:spa_config) && m.spa_config }

    generator.generate_ruby_serializers(models)
    generator.generate_js_hydrators(models)
    generator.generate_ts_types(models) if ENV['GENERATE_TYPES']
  end
end
```

**Proof of Concept:**
1. Annotate one simple model (`Studio` or `Person`)
2. Implement generator for that model
3. Verify generated code works
4. Refine DSL based on learnings

**Outcome:** Working proof of concept, validated approach.

### Stage 3: Full Model Coverage

1. Annotate remaining models (`Heat`, `Entry`, `Dance`, `Score`, etc.)
2. Solve context passing for precomputed fields
3. Replace `heats_data` serialization with generated code
4. Replace `heat_hydrator.js` with generated code
5. Verify with `compare-erb-js` tests
6. Remove hand-written serialization/hydration code

**Outcome:** Single source of truth for serialization contracts.

### Dependencies

```
Stage 1 (Ruby2JS Modernization)
    │
    ├── Prism migration
    ├── New filters (group_by, sort_by, etc.)
    └── ERB filter (extract from ErbPrismConverter)
          │
          ▼
Stage 2 (Proof of Concept)
    │
    ├── spa_serialize DSL
    ├── Generator for one model
    └── Validate approach
          │
          ▼
Stage 3 (Full Coverage)
    │
    ├── All model annotations
    ├── Context passing solution
    └── Replace hand-written code
```

Stage 1 has independent value and no urgency. Stages 2 and 3 build on Stage 1 but can be deferred until Stage 1 is complete and proven.

## What Gets Generated vs What Remains Manual

### Generated

| Component | Source | Output |
|-----------|--------|--------|
| Serializers | Model annotations | `lib/generated/spa_serializers.rb` |
| Hydrators | Model annotations | `app/javascript/generated/spa_hydrators.js` |
| Type definitions | Model annotations | `app/javascript/generated/spa_types.d.ts` |
| Shared logic | Computed blocks | Both Ruby module and JS module |
| Eager loading | `references` declarations | `includes_for_preload` methods |

### Remains Manual

| Component | Reason |
|-----------|--------|
| Controller orchestration | Business logic for which heats to load, context building |
| Top-level JSON structure | `event`, `judge`, `paths`, etc. not tied to single model |
| HTTP protocol | Request/response handling |
| Browser interactivity | Event handlers, IndexedDB, History API |

## Risk Verification (Completed)

The following risks were investigated and verified as non-blocking:

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

### Ruby-Specific Methods ✅

Methods like `group_by` and `sort_by` don't exist natively in JS, but:
- Current shared logic doesn't use them (only server-side controller code does)
- They can be added to `filter/functions.rb` following existing patterns (`select`→`filter`, `any?`→`some`)
- Implementation is straightforward AST transformation

### Block Introspection ✅

Ruby2JS can extract and convert blocks defined in model annotations:

| Scenario | Status |
|----------|--------|
| DSL-captured blocks (`computed :name do ... end`) | ✅ Works |
| Multi-line complex blocks | ✅ Works |
| Rake task timing (after `eager_load!`) | ✅ Works |
| Nested structures, case/when | ✅ Works |

**How it works:** Ruby2JS uses `block.source_location` to get `[filename, line_number]`, reads the source file, parses it, and extracts the block body from the AST.

**Caveat:** Ruby2JS reads the current file content at conversion time. This is correct behavior for code generation (rake task runs with current source).

### Remaining Unknown

**Context passing for precomputed fields** — How to specify that `dance_string` depends on `heats_same_number` context. May require explicit context declaration in annotation or convention-based approach. To be explored during implementation.

## Success Criteria

1. Model annotations are the single source of truth for serialization shape
2. Computed blocks with shared logic work identically in Ruby and JS
3. `compare-erb-js` tests pass with generated code
4. Reduced manual code in `heats_data` (~200 lines → ~50 lines)
5. Reduced manual code in `heat_hydrator.js` (~400 lines → ~100 lines)
6. Adding a new field requires only annotation change + regenerate

## Related Documents

- [ERB_TO_JS_TRANSFORMER_ARCHITECTURE.md](ERB_TO_JS_TRANSFORMER_ARCHITECTURE.md) — Modular converter design
- [OFFLINE_SCORING_COMPLETION.md](OFFLINE_SCORING_COMPLETION.md) — Offline scoring implementation plan
- [From ERB to JavaScript](https://intertwingly.net/blog/2025/11/25/ERB-Stimulus-Offline.html) — Blog post documenting current architecture
- [Ruby2JS](https://www.ruby2js.com/) — Ruby to JavaScript transpiler ([GitHub](https://github.com/ruby2js/ruby2js))
