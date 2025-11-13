# SPA Offline Scoring: Test Matrix and Implementation Plan

## Overview

This document provides a systematic plan to test and implement all scoring/judging options for the offline-capable SPA. The plan follows a test-driven approach: write tests first, then implement components to pass those tests.

## Current State

### ✅ Implemented Web Components
- `heat-page.js` - Main orchestrator
- `heat-list.js` - Heat list view
- `heat-solo.js` - Solo heat rendering (basic implementation)
- `heat-rank.js` - Finals with drag-and-drop ranking
- `heat-table.js` - Standard heat table with radio/checkbox scoring
- `heat-cards.js` - Card-based drag-and-drop scoring interface
- `heat-header.js` - Heat details (number, dance, slot display)
- `heat-info-box.js` - Contextual help and instructions
- `heat-navigation.js` - Navigation footer
- `HeatDataManager` - IndexedDB-based offline storage

### ✅ Existing Tests (210 total)
- `navigation.test.js` (17 tests) - Heat navigation and slot progression
- `semi_finals.test.js` (22 tests) - Semi-finals logic
- `start_button.test.js` (20 tests) - Emcee mode start button
- `component_selection.test.js` (20 tests) - Component selection based on category
- `heat_details.test.js` (29 tests) - Heat header and info box display
- `score_posting.test.js` (13 tests) - Score submission with offline queueing
- `heat_data_manager.test.js` (12 tests) - IndexedDB storage and sync
- `heat_solo.test.js` (19 tests) - Solo heat variations ✅
- `heat_rank.test.js` (22 tests) - Rank heat variations ✅
- `heat_table.test.js` (36 tests) - Table heat display and scoring ✅

### 🔴 Needs Implementation & Testing
Based on ERB views analysis, the following variations need systematic testing:

## Scoring Configuration Options

### Event-Level Scoring Settings (Event model)

| Setting | Values | Description |
|---------|--------|-------------|
| `open_scoring` | `'1'`, `'G'`, `'#'`, `'+'`, `'&'`, `'@'` | Open category scoring type |
| `closed_scoring` | `'G'`, `'='` (uses open_scoring), `'#'`, `'+'`, `'&'`, `'@'` | Closed category scoring type |
| `multi_scoring` | `'1'`, `'G'`, `'#'`, `'+'`, `'&'`, `'@'` | Multi-dance scoring type |
| `solo_scoring` | `'1'` (single score), `'4'` (4-part: technique/execution/presentation/showmanship) | Solo scoring type |
| `column_order` | `1` (Lead/Follow), `0` (Student/Instructor) | Column ordering preference |
| `backnums` | `true`, `false` | Display back numbers |
| `track_ages` | `true`, `false` | Track age categories |
| `ballrooms` | `1`, `2+` | Number of ballrooms |
| `heat_range_cat` | `0`, `1+` | Combine open/closed categories |
| `assign_judges` | `0`, `1+` | Judge assignment mode |
| `judge_comments` | `true`, `false` | Enable judge comments per heat |

### Scoring Type Meanings

| Type | Symbol | Description | Scores Available |
|------|--------|-------------|------------------|
| `'1'` | 1/2/3/F | Placement scoring | `['1', '2', '3', 'F', '']` |
| `'G'` | GH/G/S/B | Letter grades (Good Honor, Good, Satisfactory, Below) | `['GH', 'G', 'S', 'B', '']` (reverse order) |
| `'#'` | Number | Numeric scoring (0-100) | No predefined scores, input field |
| `'+'` | Feedback | Feedback only (Good Job With / Needs Work On) | Empty, uses feedback buttons |
| `'&'` | Number + Feedback | Numeric (1-5) plus feedback | `[]`, uses value buttons + feedback |
| `'@'` | Grade + Feedback | Letter grade (B/S/G/GH) plus feedback | `[]`, uses grade buttons + feedback |

### Judge-Level Settings (Person/Judge model)

| Setting | Values | Description |
|---------|--------|-------------|
| `sort_order` | `'back'`, `'level'` | Sort couples by back number or level |
| `show_assignments` | `'first'`, `'only'`, `'mixed'` | How to show judge assignments |
| `review_solos` | `'all'`, `'even'`, `'odd'`, `'none'` | Which solo heats to review |

### Heat-Level Properties

| Property | Source | Description |
|----------|--------|-------------|
| Category | `heat.category` | `'Open'`, `'Closed'`, `'Multi'`, `'Solo'` |
| Dance properties | `heat.dance` | `semi_finals`, `heat_length`, `uses_scrutineering?` |
| Subject count | Heat records | Affects semi-finals logic (≤8 skip to finals) |
| Slot | URL param | Multi-dance slot number (preliminaries vs finals) |
| Formations | `heat.solo.formations` | Additional people in solo heats |

## View Components Matrix

### View Selection Logic (from scores/heat.html.erb:18-26)

```ruby
if @heat.category == 'Solo'
  render 'solo_heat'
elsif @final
  render 'rank_heat'
elsif @style != 'cards' || @style == 'emcee' || @scores.empty?
  render 'table_heat'
else
  render 'cards_heat'
end
```

### 1. Solo Heat View (`heat-solo.js`) ✅ **COMPLETED**

**ERB Template:** `_solo_heat.html.erb`

**Implementation Status:** ✅ Completed and tested (19 tests passing)

**Variations Tested:**

| Test ID | Setting | Value | Expected Behavior | Status |
|---------|---------|-------|-------------------|--------|
| S1 | `solo_scoring` | `'1'` | Single numeric input (0-100) | ✅ |
| S2 | `solo_scoring` | `'4'` | Four inputs: Technique, Execution, Presentation, Showmanship (0-25 each) | ✅ |
| S3 | `column_order` | `1` | Show Lead, Follow order | ✅ |
| S4 | `column_order` | `0` | Show Student, Instructor order | ✅ |
| S5 | `formations.on_floor` | `true` | Include formation members in display | ✅ |
| S6 | `formations.on_floor` | `false` | Exclude from display (credit only) | ✅ |
| S7 | Style | `'emcee'` | Show song/artist, hide scoring, show "Start Heat" button | ✅ |
| S8 | Comments | - | Textarea for judge comments | ✅ |
| S9 | Combo dance | - | Show "Dance1 / Dance2" format | ✅ |

**Test File:** `test/javascript/heat_solo.test.js` ✅ **19 tests passing**

**Implementation Notes:**
- Fixed display_name prioritization in component (lines 91, 94, 95, 106)
- Fixed API to return formation.person.display_name in scores_controller.rb:200
- Dancer name formatting handles same-last-name consolidation ("John & Jane Smith")
- Studio determined from first dancer or instructor fallback

### 2. Rank Heat View (`heat-rank.js`) ✅ **COMPLETED**

**ERB Template:** `_rank_heat.html.erb`

**Implementation Status:** ✅ Completed and tested (22 tests passing)

**Variations Tested:**

| Test ID | Setting | Value | Expected Behavior | Status |
|---------|---------|-------|-------------------|--------|
| R1 | Initial state | - | Show all couples in semi-finals callback order | ✅ |
| R2 | Drag and drop | - | Reorder ranks, update all affected ranks | ✅ |
| R3 | `column_order` | `1` | Show Lead/Follow columns | ✅ |
| R4 | `column_order` | `0` | Show Student/Instructor columns | ✅ |
| R5 | `combine_open_and_closed` | `true` | Show "Open - " or "Closed - " prefix | ✅ |
| R6 | `track_ages` | `true` | Show age category in subject category | ✅ |
| R7 | `track_ages` | `false` | Hide age category | ✅ |
| R8 | Style | `'emcee'` | Show "Start Heat" button | ✅ |
| R9 | Scratched heats | `number <= 0` | Show line-through, opacity-50, not draggable | ✅ |
| R10 | Pro couples | - | Show "Pro" instead of level | ✅ |

**Test File:** `test/javascript/heat_rank.test.js` ✅ **22 tests passing**

**Implementation Notes:**
- Fixed column_order handling (0 vs 1) using `!== undefined ? : 1` pattern
- Fixed display_name prioritization in component (lines 258-262)
- Scratched heats correctly identified with `number <= 0`
- Drag-and-drop functionality maintains sequential rank numbering
- Empty heat handling with appropriate message

### 3. Table Heat View (`heat-table.js`) ✅ **BASIC TESTS COMPLETED**

**ERB Template:** `_table_heat.html.erb`

**Implementation Status:** ✅ Basic display and radio/number scoring tested (25 tests passing)

**Variations Tested:**

#### Basic Table Display ✅

| Test ID | Setting | Value | Expected Behavior | Status |
|---------|---------|-------|-------------------|--------|
| T1 | `column_order` | `1` | Show Back/Lead/Follow/Category/Studio | ✅ |
| T2 | `column_order` | `0` | Show Back/Student/Instructor/Category/Studio | ✅ |
| T3 | `ballrooms` | `2+` | Add Ballroom column after Back | ✅ |
| T4 | `combine_open_and_closed` | `true` | Show "Open - " or "Closed - " prefix in category | ✅ |
| T5 | `track_ages` | `true` | Include age in category display | ✅ |
| T6 | `track_ages` | `false` | Exclude age from category | ✅ |

#### Scoring Type: Radio (`'1'` or `'G'`) ✅

| Test ID | Scoring | Expected Behavior | Status |
|---------|---------|-------------------|--------|
| T7 | `'1'` | Radio buttons for 1/2/3/F/- | ✅ |
| T8 | `'G'` | Radio buttons for GH/G/S/B/- | ✅ |
| T9 | Both | Clicking radio updates score, posts to server | ✅ |

#### Scoring Type: Number (`'#'`) ✅

| Test ID | Expected Behavior | Status |
|---------|-------------------|--------|
| T10 | Show input field with pattern `^\d\d$` (two digits) | ✅ |
| T11 | Validate 0-99 range | ✅ |
| T12 | Post on blur/change | ✅ |

**Test File:** `test/javascript/heat_table.test.js` ✅ **36 tests passing**

**Implementation Notes:**
- Fixed column_order handling in buildHeaders (line 104) and buildRows (line 327)
- display_name already prioritized correctly
- Added ballroom property support to fixture factory
- Empty heats, scratched heats, and pro couples all handled correctly

#### Scoring Type: Scrutineering (semi_finals) ✅

| Test ID | Expected Behavior | Status |
|---------|-------------------|--------|
| T13 | Show single checkbox per couple (callback vote) | ✅ |
| T14 | Header shows "Callback?" | ✅ |
| T15 | Clicking checkbox toggles value '1' or '' | ✅ |

#### Scoring Type: Feedback (`'+'`)

| Test ID | Expected Behavior |
|---------|-------------------|
| T16 | Show two grids: "Good Job With" and "Needs Work On" |
| T17 | 10 buttons each: DF, T, LF, CM, RF, FW, B, AS, CB, FC |
| T18 | Clicking button toggles selection |
| T19 | Good and bad are mutually exclusive per feedback type |

#### Scoring Type: Number + Feedback (`'&'`)

| Test ID | Expected Behavior |
|---------|-------------------|
| T20 | Show "Overall" row with 5 buttons (1-5) |
| T21 | Show "Good" row with 6 buttons: F, P, FW, LF, T, S |
| T22 | Show "Needs Work" row with 6 buttons: F, P, FW, LF, T, S |
| T23 | Overall buttons toggle (only one active) |
| T24 | Good/bad buttons toggle, mutually exclusive |

#### Scoring Type: Grade + Feedback (`'@'`)

| Test ID | Expected Behavior |
|---------|-------------------|
| T25 | Show "Overall" row with 4 buttons (B/S/G/GH) |
| T26 | Show "Good" row with 6 buttons: F, P, FW, LF, T, S |
| T27 | Show "Needs Work" row with 6 buttons: F, P, FW, LF, T, S |
| T28 | Overall buttons toggle (only one active) |
| T29 | Good/bad buttons toggle, mutually exclusive |

#### Judge Comments ✅

| Test ID | Setting | Expected Behavior | Status |
|---------|---------|-------------------|--------|
| T30 | `judge_comments: true` | Show textarea under each couple | ✅ |
| T31 | `judge_comments: false` | No textarea | ✅ |
| T32 | Comment input | Debounce and post to server | ✅ |

#### Judge Assignment

| Test ID | Setting | Expected Behavior |
|---------|---------|-------------------|
| T33 | `assign_judges > 0` | Show red border on assigned back numbers |
| T34 | `show_assignments: 'first'` | Show assigned first, then others |
| T35 | `show_assignments: 'only'` | Show only assigned couples |
| T36 | `show_assignments: 'mixed'` | Show all in sort order |
| T37 | No assigned couples | Show "No couples assigned" message |

#### Ballroom Assignment ✅

| Test ID | Setting | Expected Behavior | Status |
|---------|---------|-------------------|--------|
| T38 | Multiple dances in heat | Gray separator line between dances | ✅ |
| T39 | `ballrooms > 1` | Black separator line between ballrooms (ballroom: 'B') | ✅ |

#### Sort Order

| Test ID | Setting | Expected Behavior |
|---------|---------|-------------------|
| T40 | `sort_order: 'back'` | Sort by dance_id, then back number |
| T41 | `sort_order: 'level'` | Sort by level_id, age_id, back number |
| T42 | Level sort with assignment | Assigned first within each level |

#### Emcee Mode ✅

| Test ID | Expected Behavior | Status |
|---------|-------------------|--------|
| T43 | Hide all scoring columns | ✅ |
| T44 | Show "Start Heat" button if not current heat | ✅ |
| T45 | Hide start button when current heat | ✅ |

**Test File:** `test/javascript/heat_table.test.js` ✅

### 4. Cards Heat View (`heat-cards.js`)

**ERB Template:** `_cards_heat.html.erb`

**Current Implementation:** Exists, needs testing

**Variations to Test:**

| Test ID | Setting | Expected Behavior |
|---------|---------|-------------------|
| C1 | Basic layout | Show score columns with blank column for unscored |
| C2 | `backnums: true` | Show back number prominently on cards |
| C3 | `backnums: false` | Show names on cards |
| C4 | `column_order: 1` | Lead name first on card |
| C5 | `column_order: 0` | Follow name first on card |
| C6 | `track_ages: true` | Show age on card |
| C7 | `combine_open_and_closed: true` | Show Open/Closed on card |
| C8 | Drag and drop | Move card between score columns |
| C9 | Colors by level | Apply level-specific colors (head-NV, base-NV) |

**Test File:** `test/javascript/heat_cards.test.js` (NEW)

## Navigation & Infrastructure Tests

### Already Tested (Enhance as Needed)
- ✅ Heat navigation with fractional heats
- ✅ Slot progression for multi-dance
- ✅ Semi-finals logic (≤8 skip, >8 require semis)
- ✅ Start button offline protection
- ✅ Component selection logic
- ✅ Heat header display
- ✅ Info box display
- ✅ Score posting and offline queueing
- ✅ IndexedDB data manager

### Additional Navigation Tests Needed

| Test ID | Feature | Expected Behavior |
|---------|---------|-------------------|
| N1 | Review solos: 'all' | Show all solo heats |
| N2 | Review solos: 'even' | Show only even-numbered solo heats |
| N3 | Review solos: 'odd' | Show only odd-numbered solo heats |
| N4 | Review solos: 'none' | Skip all solo heats in navigation |
| N5 | Multi-dance child heats | Navigate to slot 1 of multi-dance |
| N6 | Previous heat multi-dance | Navigate to last slot of previous multi |

**Test File:** Enhance `test/javascript/navigation.test.js`

## Implementation Plan

### Phase 1: Test Infrastructure ✅ **COMPLETED**
1. ✅ Created test helper utilities (`component_helpers.js`)
2. ✅ Created fixture factory (`fixture_factory.js`) with all data generators
3. ✅ Established component testing patterns

**Deliverables:**
- `test/javascript/helpers/fixture_factory.js` (387 lines)
- `test/javascript/helpers/component_helpers.js` (350 lines)

### Phase 2: Solo Heat Tests & Implementation ✅ **COMPLETED**
1. ✅ Wrote `test/javascript/heat_solo.test.js` (19 tests: S1-S9 + additional coverage)
2. ✅ Enhanced `heat-solo.js` to pass all tests
3. ✅ Verified behavioral parity with `_solo_heat.html.erb`

**Deliverables:**
- `test/javascript/heat_solo.test.js` (533 lines, 19 tests)
- Fixed `heat-solo.js` display_name handling
- Fixed `scores_controller.rb` formation API

### Phase 3: Rank Heat Tests & Implementation ✅ **COMPLETED**
1. ✅ Wrote comprehensive `test/javascript/heat_rank.test.js` (22 tests: R1-R10 + variations)
2. ✅ Enhanced `heat-rank.js` to pass all tests
3. ✅ Verified drag-and-drop rank updates

**Deliverables:**
- `test/javascript/heat_rank.test.js` (505 lines, 22 tests)
- Fixed `heat-rank.js` column_order and display_name handling
- Fixed `fixture_factory.js` createEntry and createSubject

### Phase 4: Table Heat Tests & Implementation (Weeks 4-6)
1. ✅ **Week 4 Complete**: Basic display, radio/number scoring (T1-T12, 25 tests)
   - ✅ Wrote `test/javascript/heat_table.test.js` with 25 tests
   - ✅ Enhanced `heat-table.js` column_order handling
   - ✅ All 199 tests passing
2. 🔴 **Week 5 Pending**: Scrutineering, feedback scoring (T13-T29)
3. 🔴 **Week 6 Pending**: Comments, assignments, sorting, emcee (T30-T45)

**Deliverables (Week 4):**
- `test/javascript/heat_table.test.js` (25 tests)
- Fixed `heat-table.js` column_order handling (lines 104, 327)
- Enhanced `fixture_factory.js` with ballroom property support

### Phase 5: Cards Heat Tests & Implementation (Week 7)
1. Write `test/javascript/heat_cards.test.js` (9 tests: C1-C9)
2. Enhance `heat-cards.js` to pass all tests
3. Verify drag-and-drop works correctly

### Phase 6: Navigation Enhancements (Week 8)
1. Enhance `test/javascript/navigation.test.js` (6 new tests: N1-N6)
2. Update navigation logic to handle review_solos filtering
3. Verify multi-dance slot navigation

### Phase 7: Integration & System Testing (Week 9)
1. Manual testing with demo database covering all option combinations
2. Test offline sync after complex scoring sessions
3. Test live ActionCable updates during scoring
4. Performance testing with large heats (50+ couples)

### Phase 8: Retirement of ERB Views (Week 10)
1. Create feature flag to toggle between SPA and ERB views
2. Get user feedback from real event with SPA enabled
3. If successful, remove ERB views and stimulus controllers
4. Clean up deprecated code

## Test Execution Strategy

### Test Organization
```
test/javascript/
  ├── heat_solo.test.js          (NEW - 9 tests)
  ├── heat_rank.test.js          (ENHANCE - add 10 tests)
  ├── heat_table.test.js         (NEW - 45 tests)
  ├── heat_cards.test.js         (NEW - 9 tests)
  ├── navigation.test.js         (ENHANCE - add 6 tests)
  ├── helpers/
  │   ├── component_helpers.js   (NEW - rendering utilities)
  │   └── fixture_factory.js     (NEW - test data generation)
  └── [existing tests continue to work]
```

### Test Data Generation Pattern
Each test should generate data that exercises specific options:

```javascript
import { createHeatData } from './helpers/fixture_factory';

test('Solo heat with 4-part scoring', () => {
  const data = createHeatData({
    category: 'Solo',
    solo_scoring: '4',
    judge_comments: false
  });

  const component = renderComponent('<heat-solo>', data);

  expect(component.querySelector('input[name="technique"]')).toBeTruthy();
  expect(component.querySelector('input[name="execution"]')).toBeTruthy();
  // ...
});
```

## Success Criteria

### Per Phase
- All new tests pass (100% pass rate)
- No regressions in existing tests
- Manual verification with demo database confirms expected behavior
- Code review completed

### Overall Project Success
- **219+ total tests** (210 completed + ~9 remaining)
  - ✅ 210 tests passing (133 original + 19 solo + 22 rank + 36 table)
  - 🔴 ~9 table heat tests remaining (T16-T29, T33-T37, T40-T42: feedback, assignments, sorting)
- All scoring options tested and working
- Offline sync reliable across all scoring types
- Performance acceptable (< 200ms render time per heat)
- User acceptance from real event
- ERB views successfully retired

## Risk Mitigation

### Identified Risks
1. **Feedback scoring complexity** - Most complex UI with many states
   - Mitigation: Extra time allocated (Weeks 5-6), break into smaller tests
2. **Judge assignment logic** - Complex filtering and display rules
   - Mitigation: Separate tests for each show_assignments mode
3. **Offline sync with complex scoring** - Potential data loss
   - Mitigation: Extra integration tests, careful testing of queue logic
4. **Browser compatibility** - IndexedDB/drag-drop may have issues
   - Mitigation: Test on multiple browsers (Chrome, Safari, Firefox)

### Rollback Plan
- Keep ERB views operational until Phase 8
- Feature flag allows instant rollback if issues discovered
- Database schema unchanged, so no migration risks

## Notes

- Current open feedback implementation manually verified to work
- Total estimated time: 10 weeks (assumes 1 developer, part-time)
- Can parallelize some phases if multiple developers available
- Priority order: Table > Solo > Rank > Cards (based on frequency of use)
