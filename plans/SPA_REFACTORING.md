# SPA Refactoring Plan

## Overview

This document outlines a comprehensive refactoring of the judge scoring SPA to improve code organization, reduce coupling, and establish clear architectural boundaries.

**Last Updated:** 2025-11-15 (after Priority 1 completion and offline scoring fixes)

## Current State (As of 2025-11-15)

**Web Components** (1,659 lines):
- `heat_data_manager.js`: 564 lines (+39) - IndexedDB, dirty scores, connectivity, sync, **offline merging**
- `heat-page.js`: 781 lines (+12) - orchestration, navigation, version checks, popstate
- `heat-navigation.js`: 314 lines (unchanged) - navigation UI with connectivity display

**Stimulus Controllers** (611 lines, cleaned up):
- `score_controller.js`: 515 lines (-15) - keyboard/touch nav, drag-and-drop, scoring
  - ✅ **No offline-capable bypasses** (removed in Priority 1)
- `open_feedback_controller.js`: 96 lines (-14) - feedback button clicks
  - ✅ **No offline-capable bypasses** (removed in Priority 1)

**Priority 1 Status: ✅ COMPLETE** (commit 835754e7)
- All Stimulus dependencies removed from SPA
- Clean separation: ERB = Stimulus, SPA = Web Components
- No `data-controller` or `data-offline-capable` attributes remain

**New Complexity Since Plan** (commit 0ebc0811):
- Offline score field preservation added (lines 396-402 in heat_data_manager.js)
- Cache invalidation after batch upload (line 509-512)
- Score merging with current values to prevent field loss
- `saveScore()` grew from ~60 to 95 lines due to merging logic

## Target State

**Clean separation of concerns**:
- ERB views → Use Stimulus controllers (unchanged)
- SPA views → Web components handle everything (no Stimulus)

**Extracted classes**:
- `ConnectivityTracker` - network status, events, batch upload triggers
- `DirtyScoresQueue` - IndexedDB dirty score operations
- `HeatNavigator` - navigation orchestration
- `HeatDataManager` - data fetching/caching only

**Benefits**:
- ✅ Clear architectural boundary (ERB = Stimulus, SPA = Components)
- ✅ Single ownership (each component owns its interactions)
- ✅ No conditional logic (controllers don't know about SPA)
- ✅ Easier testing (test components in isolation)
- ✅ Simpler maintenance (clear responsibilities)

---

## Test Baseline (Updated 2025-11-15)

| Test Suite | Status | Details |
|------------|--------|---------|
| **JavaScript (Vitest)** | ✅ **Pass** | 287/287 tests |
| **Rails Unit/Integration** | ✅ **Pass** | 1107 runs, 5135 assertions |
| **Rails System Tests** | ✅ **Pass** | 129 runs, 319 assertions (6 skips) |

**Total: 1523 passing tests** (+7 from offline scoring fixes)

All tests must continue passing after each priority phase.

---

## Priority 1: Remove Stimulus from SPA

**Goal**: Web components handle all SPA interactions directly, eliminating Stimulus dependency.

**Estimated Time**: 10-14 hours (1-2 focused days)

### Files to Modify

#### 1. `app/javascript/components/heat-types/heat-table.js`

**Current** (lines 584-586):
```javascript
this.innerHTML = `
  <div data-controller="score" data-offline-capable="true" ...>
    <!-- content -->
  </div>
`;
```

**Changes**:
- **Remove**: `data-controller="score"` attribute
- **Remove**: `data-offline-capable="true"` attribute
- **Remove**: `data-controller="open-feedback"` from feedback rows (line 291)
- **Add**: Direct event listeners in `connectedCallback()`

**Logic to port from `score_controller.js`**:

**Keyboard Navigation** (lines 11-64):
```javascript
setupKeyboardListeners() {
  this.keydownHandler = (event) => {
    const isFormElement = ['INPUT', 'TEXTAREA'].includes(event.target.nodeName);

    // Arrow keys for table navigation (NOT heat navigation - that's in heat-page)
    if (event.key === 'ArrowUp' && !isFormElement) {
      event.preventDefault();
      this.moveUp();
    } else if (event.key === 'ArrowDown') {
      event.preventDefault();
      this.moveDown();
    } else if (event.key === 'Tab') {
      event.preventDefault();
      this.handleTabNavigation(event.shiftKey);
    } else if (event.key === 'Escape') {
      this.unselect();
      this.unhighlight();
      if (document.activeElement) document.activeElement.blur();
    } else if (event.key === ' ' || event.key === 'Enter') {
      if (!isFormElement) this.startHeat();
    }
  };

  document.body.addEventListener('keydown', this.keydownHandler);
}
```

**Touch/Swipe Gestures** (lines 67-88):
```javascript
setupTouchListeners() {
  this.touchStart = null;

  this.touchStartHandler = (event) => {
    this.touchStart = event.touches[0];
  };

  this.touchEndHandler = (event) => {
    // Note: Swipe for heat navigation is handled by heat-page
    // This is only for up/down swipes to show heat list
    const direction = this.swipe(event);
    if (direction === 'up') {
      // Dispatch event for heat-page to handle
      this.dispatchEvent(new CustomEvent('show-heat-list', { bubbles: true }));
    }
  };

  document.body.addEventListener('touchstart', this.touchStartHandler);
  document.body.addEventListener('touchend', this.touchEndHandler);
}

swipe(event) {
  if (!this.touchStart) return null;
  const stop = event.changedTouches[0];
  if (stop.identifier !== this.touchStart.identifier) return null;

  const deltaX = stop.clientX - this.touchStart.clientX;
  const deltaY = stop.clientY - this.touchStart.clientY;
  const height = document.documentElement.clientHeight;
  const width = document.documentElement.clientWidth;

  if (Math.abs(deltaX) > width/2 && Math.abs(deltaY) < height/4) {
    return deltaX > 0 ? 'right' : 'left';
  } else if (Math.abs(deltaY) > height/2 && Math.abs(deltaX) < width/4) {
    return deltaY > 0 ? 'down' : 'up';
  }
  return null;
}
```

**Drag-and-Drop for Cards Style** (lines 330-392):
```javascript
setupDragAndDrop() {
  this.subjects = new Map();
  this.selected = null;

  const draggableElements = this.querySelectorAll('[draggable="true"]');

  for (const subject of draggableElements) {
    if (!subject.dataset.heat) continue;
    this.subjects.set(subject.id, subject);

    subject.addEventListener('dragstart', (event) => {
      this.select(subject);
      subject.style.opacity = 0.4;
      event.dataTransfer.setData('application/drag-id', subject.id);
      event.dataTransfer.effectAllowed = 'move';
    });

    subject.addEventListener('mouseup', (event) => {
      event.stopPropagation();
      this.toggle(subject);
      this.unhighlight();
    });

    subject.addEventListener('touchend', (event) => {
      if (this.swipe(event)) return;
      event.preventDefault();
      this.toggle(subject);
    });
  }

  const scoreTargets = this.querySelectorAll('[data-score]');
  for (const score of scoreTargets) {
    score.addEventListener('dragover', (event) => {
      event.preventDefault();
      return true;
    });

    score.addEventListener('dragenter', (event) => {
      score.classList.add('bg-yellow-200');
      event.preventDefault();
    });

    score.addEventListener('dragleave', () => {
      score.classList.remove('bg-yellow-200');
    });

    score.addEventListener('drop', (event) => {
      score.classList.remove('bg-yellow-200');
      const sourceId = event.dataTransfer.getData('application/drag-id');
      const source = document.getElementById(sourceId);
      this.moveToScore(source, score);
    });

    score.addEventListener('mouseup', () => {
      this.moveToScore(this.selected, score);
    });

    score.addEventListener('touchend', (event) => {
      if (this.swipe(event)) return;
      event.preventDefault();
      this.moveToScore(this.selected, score);
      this.unhighlight();
    });
  }
}

moveToScore(source, score) {
  if (!source) return;
  const parent = source.parentElement;
  const back = source.querySelector('span');

  source.style.opacity = 1;
  back.style.opacity = 0.5;

  const before = [...score.children].find(child =>
    child.draggable && child.querySelector('span').textContent >= back.textContent
  );

  if (before) {
    score.insertBefore(source, before);
  } else {
    score.appendChild(source);
  }

  // Save via HeatDataManager
  heatDataManager.saveScore(this.judgeData.id, {
    heat: parseInt(source.dataset.heat),
    slot: this.slot || null,
    score: score.dataset.score || ''
  }).then(() => {
    back.style.opacity = 1;
    back.classList.remove('text-red-500');
  }).catch(() => {
    parent.appendChild(source);
    back.classList.add('text-red-500');
  });
}
```

**Radio/Checkbox Handlers** (lines 454-482):
```javascript
setupRadioCheckboxListeners() {
  const buttons = this.querySelectorAll('input[type=radio], input[type=checkbox]');

  for (const button of buttons) {
    button.disabled = false;

    button.addEventListener('change', async (event) => {
      const callbacks = parseInt(this.getAttribute('data-callbacks') || '0');

      // Enforce maximum number of callbacks
      if (callbacks && button.type === 'checkbox' && button.checked) {
        const checkedCount = this.querySelectorAll('input[type="checkbox"]:checked').length;
        if (checkedCount > callbacks) {
          event.preventDefault();
          event.stopPropagation();
          button.checked = false;
          return;
        }
      }

      const scoreData = {
        heat: parseInt(button.name),
        slot: this.slot || null,
        score: button.type === 'radio' ? button.value : (button.checked ? 1 : '')
      };

      try {
        await heatDataManager.saveScore(this.judgeData.id, scoreData);
        button.classList.remove('border-red-500');

        // Dispatch event for heat-page to update in-memory data
        this.dispatchEvent(new CustomEvent('score-updated', {
          bubbles: true,
          detail: scoreData
        }));
      } catch (error) {
        button.classList.add('border-red-500');
      }
    });
  }
}
```

**Comments Handlers** (lines 409-452):
```javascript
setupCommentsListeners() {
  const comments = this.querySelectorAll('textarea[data-score-target="comments"]');

  for (const comment of comments) {
    comment.disabled = false;
    let commentTimeout = null;

    comment.addEventListener('input', () => {
      comment.classList.remove('bg-gray-50');
      comment.classList.add('bg-yellow-200');

      if (commentTimeout) clearTimeout(commentTimeout);

      commentTimeout = setTimeout(() => {
        if (comment.dataset.value !== comment.value) {
          comment.dispatchEvent(new Event('change'));
        }
        commentTimeout = null;
      }, 10000);
    });

    comment.addEventListener('change', async () => {
      comment.disabled = true;

      const scoreData = {
        heat: parseInt(comment.dataset.heat),
        comments: comment.value
      };

      try {
        await heatDataManager.saveScore(this.judgeData.id, scoreData);
        comment.disabled = false;
        comment.classList.add('bg-gray-50');
        comment.classList.remove('bg-yellow-200');
        comment.dataset.value = comment.value;
        comment.style.backgroundColor = null;

        // Dispatch event for heat-page to update in-memory data
        this.dispatchEvent(new CustomEvent('score-updated', {
          bubbles: true,
          detail: scoreData
        }));
      } catch (error) {
        comment.disabled = false;
        comment.style.backgroundColor = '#F00';
      }
    });

    // Auto-resize textarea
    comment.rows = 1;
    comment.style.height = comment.scrollHeight + 'px';
    comment.addEventListener('input', () => {
      comment.style.height = 0;
      comment.style.height = comment.scrollHeight + 'px';
    });
  }
}
```

**Feedback Buttons** (from `open_feedback_controller.js` lines 28-107):
```javascript
setupFeedbackListeners() {
  const feedbackRows = this.querySelectorAll('.open-fb-row');

  for (const row of feedbackRows) {
    // Highlight previous row on hover
    const previous = row.previousElementSibling;
    row.addEventListener('mouseenter', () => {
      if (previous) previous.classList.add('bg-yellow-200');
    });
    row.addEventListener('mouseleave', () => {
      if (previous) previous.classList.remove('bg-yellow-200');
    });

    // Setup button handlers
    const buttons = row.querySelectorAll('button');
    for (const button of buttons) {
      button.disabled = false;

      const span = button.querySelector('span');
      const abbr = button.querySelector('abbr');
      if (span && abbr) {
        abbr.title = span.textContent;
        const feedback = button.parentElement.dataset.value.split(' ');
        if (feedback.includes(abbr.textContent)) {
          button.classList.add('selected');
        }
      }

      button.addEventListener('click', async () => {
        const feedbackType = button.parentElement.classList.contains('good') ? 'good' :
          (button.parentElement.classList.contains('bad') ? 'bad' : 'value');
        const feedbackValue = button.querySelector('abbr').textContent;

        const scoreData = {
          heat: parseInt(row.dataset.heat),
          slot: this.slot || null,
          [feedbackType]: feedbackValue
        };

        try {
          const response = await heatDataManager.saveScore(this.judgeData.id, scoreData);

          // Update UI based on response
          if (response && !response.error) {
            const sections = button.parentElement.parentElement.children;
            for (const section of sections) {
              const sectionType = section.classList.contains('good') ? 'good' :
                (section.classList.contains('bad') ? 'bad' : 'value');
              const feedback = (response[sectionType] || '').split(' ');

              for (const btn of section.querySelectorAll('button')) {
                if (feedback.includes(btn.querySelector('abbr').textContent)) {
                  btn.classList.add('selected');
                } else {
                  btn.classList.remove('selected');
                }
              }
            }
          }

          // Dispatch event for heat-page to update in-memory data
          this.dispatchEvent(new CustomEvent('score-updated', {
            bubbles: true,
            detail: scoreData
          }));
        } catch (error) {
          console.error('Failed to save feedback:', error);
        }
      });
    }
  }
}
```

**Updated connectedCallback**:
```javascript
connectedCallback() {
  // Make this element transparent in layout
  const nativeStyle = Object.getOwnPropertyDescriptor(HTMLElement.prototype, 'style').get.call(this);
  nativeStyle.display = 'contents';

  // Existing initialization...
  this.parseAttributes();

  // NEW: Setup all interaction listeners
  this.setupKeyboardListeners();
  this.setupTouchListeners();
  this.setupDragAndDrop();
  this.setupRadioCheckboxListeners();
  this.setupCommentsListeners();
  this.setupFeedbackListeners();

  // Render
  this.render();
}
```

**Updated disconnectedCallback**:
```javascript
disconnectedCallback() {
  // Clean up event listeners
  if (this.keydownHandler) {
    document.body.removeEventListener('keydown', this.keydownHandler);
  }
  if (this.touchStartHandler) {
    document.body.removeEventListener('touchstart', this.touchStartHandler);
    document.body.removeEventListener('touchend', this.touchEndHandler);
  }
}
```

#### 2. `app/javascript/components/heat-types/heat-cards.js`

**Changes**: Same drag-and-drop logic as heat-table (already has most of it)
- Remove `data-controller="score"` from template
- Ensure keyboard/touch listeners are present

#### 3. `app/javascript/components/heat-types/heat-rank.js`

**Changes**: Same drag-and-drop logic for finals ranking
- Remove `data-controller="score"` from template
- Already has drag-and-drop, verify completeness

#### 4. `app/javascript/components/heat-types/heat-solo.js`

**Changes**: Minimal (solos use comments, no drag-and-drop)
- Remove `data-controller="score"` from template
- Ensure comments listeners work

#### 5. `app/javascript/controllers/score_controller.js`

**Changes**: Remove all conditional `offline-capable` bypasses
- **Delete** lines 16-18 (arrow key bypass)
- **Delete** lines 22-23 (arrow key bypass)
- **Delete** lines 74-76 (touch bypass)
- **Delete** lines 200-206 (post bypass)
- **Delete** line 203 (console.debug)
- **Delete** line 208 (console.debug)

Controller should work unchanged for ERB views.

#### 6. `app/javascript/controllers/open_feedback_controller.js`

**Changes**: Remove conditional `offline-capable` bypass
- **Delete** lines 55-65 (fetch bypass and event dispatch)
- **Delete** line 57 (console.debug)
- **Delete** line 67 (console.debug)

Controller should work unchanged for ERB views.

### Testing Checklist

After completing changes:

**JavaScript Tests** (should all still pass):
```bash
npm run test:run
```
- ✅ 280/280 tests passing

**Manual SPA Testing**:
1. ✅ Navigate to judge SPA: `/scores/:judge/spa`
2. ✅ Select heat with radio/checkbox scoring
3. ✅ Click radio buttons → scores save
4. ✅ Click checkboxes → scores save (max limit enforced)
5. ✅ Type in comments → saves after 10s or on blur
6. ✅ Navigate with arrow keys (up/down within heat)
7. ✅ Navigate with arrow keys (left/right between heats)
8. ✅ Navigate with swipe gestures
9. ✅ Drag-and-drop couple to different score
10. ✅ Click feedback buttons (good/bad/value)
11. ✅ Go offline, make changes → see pending count
12. ✅ Come back online → pending scores upload
13. ✅ Browser back button → returns to previous heat

**Manual ERB Testing** (verify controllers still work):
1. ✅ Navigate to judge ERB view: `/scores/:judge?heat=X`
2. ✅ All same interactions work
3. ✅ Arrow keys, drag-and-drop, radio/checkbox, etc.

**Rails Tests** (should all still pass):
```bash
PARALLEL_WORKERS=0 bin/rails test
PARALLEL_WORKERS=0 bin/rails test:system
```
- ✅ 1107/1107 unit/integration tests passing
- ✅ 129/129 system tests passing

### Commit Point

```bash
git add -A
git commit -m "Remove Stimulus from SPA - web components handle all interactions

Web components now handle all SPA interactions directly:
- Keyboard navigation (arrow keys, tab, escape)
- Touch gestures (swipes, taps)
- Drag-and-drop scoring
- Radio/checkbox/textarea event handling
- Feedback button clicks
- Direct calls to HeatDataManager (no controller intermediary)

Stimulus controllers unchanged for ERB views:
- Removed offline-capable conditional bypasses
- Controllers work normally for traditional views
- Clean separation: ERB = Stimulus, SPA = Web Components

Files modified:
- heat-table.js: Added all interaction listeners
- heat-cards.js: Verified drag-and-drop completeness
- heat-rank.js: Verified drag-and-drop completeness
- heat-solo.js: Verified comments handling
- score_controller.js: Removed offline-capable bypasses
- open_feedback_controller.js: Removed offline-capable bypasses

All tests passing: 287 JS + 1107 Rails + 129 System = 1523 total
"
```

---

## Priority 2a: Extract ScoreMergeHelper (NEW)

**Goal**: Extract complex score field merging logic from HeatDataManager.

**Rationale**: The offline fixes (commit 0ebc0811) added complex merging logic to preserve score fields when saving offline. This logic is now ~30 lines within `saveScore()` and violates single responsibility. Extracting it will:
- Make saveScore() cleaner and easier to understand
- Allow testing merge logic in isolation
- Reuse merge logic if needed elsewhere (e.g., batch upload)

**Estimated Time**: 2-4 hours (half day)

### Current Problem

**`heat_data_manager.js` lines 396-402** (merging for offline save):
```javascript
// Save offline
const mergedData = {
  score: data.score || data.value || currentScore.value || '',
  comments: data.comments !== undefined ? data.comments : (currentScore.comments || ''),
  good: data.good !== undefined ? data.good : (currentScore.good || ''),
  bad: data.bad !== undefined ? data.bad : (currentScore.bad || '')
};

await this.addDirtyScore(judgeId, data.heat, data.slot || null, mergedData);
```

This merging handles:
1. **Field alias**: `score` vs `value` (both used in different contexts)
2. **Partial updates**: Only update fields present in request
3. **Default values**: Empty string for missing fields
4. **Preservation**: Keep existing values if not in update

**Complexity**: This logic is duplicated conceptually in the optimistic update section (lines 409-423) which determines which fields to return.

### Files to Create

#### `app/javascript/helpers/score_merge_helper.js`

**Purpose**: Handle score field merging for offline saves and optimistic updates.

```javascript
/**
 * ScoreMergeHelper - Score field merging logic
 *
 * Handles merging of score updates with current values for offline saves
 * and generating optimistic update responses.
 */

class ScoreMergeHelper {
  /**
   * Merge score update with current values for offline storage
   *
   * @param {Object} update - The score update {score?, value?, good?, bad?, comments?}
   * @param {Object} current - Current score values {value?, good?, bad?, comments?}
   * @returns {Object} Merged data for offline storage {score, comments, good, bad}
   */
  static mergeForOffline(update, current = {}) {
    return {
      score: update.score || update.value || current.value || '',
      comments: update.comments !== undefined ? update.comments : (current.comments || ''),
      good: update.good !== undefined ? update.good : (current.good || ''),
      bad: update.bad !== undefined ? update.bad : (current.bad || '')
    };
  }

  /**
   * Generate optimistic update response (only fields that were updated)
   *
   * @param {Object} update - The score update {score?, value?, good?, bad?, comments?}
   * @returns {Object} Response with only updated fields {value?, good?, bad?, comments?}
   */
  static generateOptimisticResponse(update) {
    const result = {};

    if (update.value !== undefined || update.score !== undefined) {
      result.value = update.value || update.score;
    }
    if (update.good !== undefined) {
      result.good = update.good;
    }
    if (update.bad !== undefined) {
      result.bad = update.bad;
    }
    if (update.comments !== undefined) {
      result.comments = update.comments;
    }

    return result;
  }

  /**
   * Normalize score field names (score → value)
   *
   * @param {Object} data - Data with possibly mixed field names
   * @returns {Object} Data with normalized field names
   */
  static normalizeFieldNames(data) {
    const normalized = { ...data };

    if (normalized.score !== undefined && normalized.value === undefined) {
      normalized.value = normalized.score;
      delete normalized.score;
    }

    return normalized;
  }
}

export default ScoreMergeHelper;
```

### Files to Update

#### `app/javascript/helpers/heat_data_manager.js`

**Import**:
```javascript
import ScoreMergeHelper from 'helpers/score_merge_helper';
```

**Update `saveScore()` offline section** (lines 395-423):

**Before** (30 lines of merging logic):
```javascript
// Save offline
const mergedData = {
  score: data.score || data.value || currentScore.value || '',
  comments: data.comments !== undefined ? data.comments : (currentScore.comments || ''),
  good: data.good !== undefined ? data.good : (currentScore.good || ''),
  bad: data.bad !== undefined ? data.bad : (currentScore.bad || '')
};

await this.addDirtyScore(judgeId, data.heat, data.slot || null, mergedData);
console.debug('[HeatDataManager] Score saved offline with merged data:', mergedData);

// Return optimistic update data - only include fields that were in the request
const result = {};
if (data.value !== undefined || data.score !== undefined) {
  result.value = data.value || data.score;
}
if (data.good !== undefined) {
  result.good = data.good;
}
if (data.bad !== undefined) {
  result.bad = data.bad;
}
if (data.comments !== undefined) {
  result.comments = data.comments;
}
return result;
```

**After** (6 lines using helper):
```javascript
// Save offline
const mergedData = ScoreMergeHelper.mergeForOffline(data, currentScore);

await this.addDirtyScore(judgeId, data.heat, data.slot || null, mergedData);
console.debug('[HeatDataManager] Score saved offline with merged data:', mergedData);

// Return optimistic update data - only include fields that were in the request
return ScoreMergeHelper.generateOptimisticResponse(data);
```

**Benefit**: Reduced from 30 lines to 6 lines, clearer intent.

### Update Import Maps

**`config/importmap.rb`**:

**Add**:
```ruby
pin "helpers/score_merge_helper", to: "helpers/score_merge_helper.js", preload: true
```

### Testing Checklist

**JavaScript Tests**:
```bash
npm run test:run
```
- ✅ 287/287 tests passing (especially heat_data_manager.test.js saveScore tests)

**Add new tests** for `score_merge_helper.test.js`:
```javascript
import { describe, it, expect } from 'vitest'
import ScoreMergeHelper from '../../app/javascript/helpers/score_merge_helper'

describe('ScoreMergeHelper', () => {
  describe('mergeForOffline', () => {
    it('merges partial update with current values', () => {
      const update = { good: 'F P' }
      const current = { value: '3', good: 'F', bad: '', comments: 'test' }

      const merged = ScoreMergeHelper.mergeForOffline(update, current)

      expect(merged.score).toBe('3')  // Preserved from current.value
      expect(merged.good).toBe('F P')  // Updated
      expect(merged.bad).toBe('')  // Preserved
      expect(merged.comments).toBe('test')  // Preserved
    })

    it('handles empty current values', () => {
      const update = { value: '4', good: 'T' }
      const current = {}

      const merged = ScoreMergeHelper.mergeForOffline(update, current)

      expect(merged.score).toBe('4')
      expect(merged.good).toBe('T')
      expect(merged.bad).toBe('')  // Default
      expect(merged.comments).toBe('')  // Default
    })

    it('prefers score over value in update', () => {
      const update = { score: 'S', value: '5' }

      const merged = ScoreMergeHelper.mergeForOffline(update, {})

      expect(merged.score).toBe('S')
    })
  })

  describe('generateOptimisticResponse', () => {
    it('returns only updated fields', () => {
      const update = { value: '3', good: 'F' }

      const response = ScoreMergeHelper.generateOptimisticResponse(update)

      expect(response.value).toBe('3')
      expect(response.good).toBe('F')
      expect(response.bad).toBeUndefined()
      expect(response.comments).toBeUndefined()
    })

    it('handles empty update', () => {
      const update = {}

      const response = ScoreMergeHelper.generateOptimisticResponse(update)

      expect(Object.keys(response)).toHaveLength(0)
    })
  })
})
```

**Manual Testing**:
1. ✅ Save score offline → fields preserved correctly
2. ✅ Update only good feedback offline → value/bad/comments preserved
3. ✅ Batch upload → all fields present
4. ✅ Optimistic UI updates → only changed fields update

**Rails Tests**:
```bash
PARALLEL_WORKERS=0 bin/rails test
PARALLEL_WORKERS=0 bin/rails test:system
```
- ✅ All tests still passing

### Commit Point

```bash
git add -A
git commit -m "Extract score merging logic into ScoreMergeHelper

Created ScoreMergeHelper (helpers/score_merge_helper.js):
- mergeForOffline(): Merge partial updates with current values
- generateOptimisticResponse(): Return only updated fields
- normalizeFieldNames(): Handle score vs value field aliases

Simplified HeatDataManager.saveScore():
- Reduced offline save section from 30 lines to 6 lines
- Clearer intent and easier to understand
- Merging logic now testable in isolation

Benefits:
- Single responsibility for merging logic
- Reusable across codebase
- Easier to test complex merge scenarios
- No behavior changes

Files created:
- helpers/score_merge_helper.js (new)
- test/javascript/score_merge_helper.test.js (new, 8 tests)

Files modified:
- helpers/heat_data_manager.js (simplified)
- config/importmap.rb (added score_merge_helper pin)

All tests passing: 295 JS + 1107 Rails + 129 System = 1531 total
"
```

---

## Priority 2b-d: Split HeatDataManager

**Goal**: Separate concerns - connectivity tracking, dirty queue, data fetching.

**Estimated Time**: 8-13 hours (1-2 focused days)

### Files to Create

#### 1. `app/javascript/helpers/connectivity_tracker.js`

**Purpose**: Track network connectivity based on actual request success/failure.

**Extracted from** `heat_data_manager.js` lines 21, 33-62, 347, 373-374, 377-378, 414-415, 422, 430

```javascript
/**
 * ConnectivityTracker - Network connectivity tracking and event dispatching
 *
 * Tracks actual network connectivity based on request success/failure,
 * dispatches events when connectivity changes, and triggers batch uploads
 * when transitioning from offline to online.
 */

class ConnectivityTracker {
  constructor() {
    this.isConnected = navigator.onLine;
  }

  /**
   * Update connectivity status based on network request success/failure
   * @param {boolean} connected - Whether the network request succeeded
   * @param {number} judgeId - The judge ID (for triggering batch upload on reconnection)
   * @param {Function} batchUploadCallback - Callback to trigger batch upload
   */
  updateConnectivity(connected, judgeId = null, batchUploadCallback = null) {
    const wasConnected = this.isConnected;
    this.isConnected = connected;

    // Dispatch connectivity change event
    if (wasConnected !== connected) {
      console.debug('[ConnectivityTracker] Connectivity changed:',
        wasConnected ? 'online→offline' : 'offline→online');
      document.dispatchEvent(new CustomEvent('connectivity-changed', {
        detail: { connected, wasConnected }
      }));

      // If transitioning from offline to online, trigger batch upload
      if (!wasConnected && connected && judgeId && batchUploadCallback) {
        console.debug('[ConnectivityTracker] Reconnected - triggering batch upload');
        batchUploadCallback(judgeId).then(result => {
          if (result.succeeded && result.succeeded.length > 0) {
            console.debug('[ConnectivityTracker] Reconnection sync:',
              result.succeeded.length, 'scores uploaded');
            document.dispatchEvent(new CustomEvent('pending-count-changed', { bubbles: true }));
          }
        }).catch(err => {
          console.debug('[ConnectivityTracker] Reconnection sync failed:', err);
        });
      }
    }
  }

  /**
   * Get current connectivity status
   * @returns {boolean}
   */
  getStatus() {
    return this.isConnected;
  }
}

// Export singleton instance
export const connectivityTracker = new ConnectivityTracker();
```

#### 2. `app/javascript/helpers/dirty_scores_queue.js`

**Purpose**: Manage dirty scores queue in IndexedDB.

**Extracted from** `heat_data_manager.js` lines 11-14, 67-278

```javascript
/**
 * DirtyScoresQueue - IndexedDB management for offline score queue
 *
 * Manages the queue of scores that failed to upload or were entered offline.
 * Uses IndexedDB for persistence across page reloads.
 */

const DB_NAME = 'showcase_dirty_scores';
const DB_VERSION = 1;
const STORE_NAME = 'dirty_scores';

class DirtyScoresQueue {
  constructor() {
    this.db = null;
    this.initPromise = null;
  }

  /**
   * Initialize the IndexedDB database
   * @returns {Promise<IDBDatabase>}
   */
  async init() {
    if (this.initPromise) {
      return this.initPromise;
    }

    this.initPromise = new Promise((resolve, reject) => {
      console.debug('[DirtyScoresQueue] init called, DB version:', DB_VERSION);
      this.openDB().then(resolve).catch(reject);
    });

    return this.initPromise;
  }

  /**
   * Open IndexedDB connection
   * @returns {Promise<IDBDatabase>}
   */
  openDB() {
    return new Promise((resolve, reject) => {
      console.debug('[DirtyScoresQueue] Opening IndexedDB...');
      const request = indexedDB.open(DB_NAME, DB_VERSION);

      request.onerror = () => {
        console.error('[DirtyScoresQueue] Failed to open IndexedDB:', request.error);
        reject(request.error);
      };

      request.onsuccess = () => {
        this.db = request.result;
        console.debug('[DirtyScoresQueue] IndexedDB opened successfully');
        resolve(this.db);
      };

      request.onupgradeneeded = (event) => {
        console.debug('[DirtyScoresQueue] Upgrade needed, old version:',
          event.oldVersion, 'new version:', event.newVersion);
        const db = event.target.result;

        if (!db.objectStoreNames.contains(STORE_NAME)) {
          console.debug('[DirtyScoresQueue] Creating dirty scores object store');
          const objectStore = db.createObjectStore(STORE_NAME, { keyPath: 'judge_id' });
          objectStore.createIndex('judge_id', 'judge_id', { unique: true });
          console.debug('[DirtyScoresQueue] Object store created');
        }
      };
    });
  }

  /**
   * Ensure IndexedDB is open
   * @returns {Promise<IDBDatabase>}
   */
  async ensureOpen() {
    if (!this.db) {
      await this.init();
    }
    return this.db;
  }

  /**
   * Add or update a dirty score (last write wins)
   * @param {number} judgeId
   * @param {number} heatId
   * @param {number|null} slot
   * @param {Object} scoreData - {score, comments, good, bad}
   */
  async addDirtyScore(judgeId, heatId, slot = 1, scoreData) {
    await this.ensureOpen();

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([STORE_NAME], 'readwrite');
      const objectStore = transaction.objectStore(STORE_NAME);
      const request = objectStore.get(judgeId);

      request.onsuccess = () => {
        const record = request.result || {
          judge_id: judgeId,
          timestamp: Date.now(),
          dirty_scores: []
        };

        // Find existing dirty score for this heat/slot
        // Normalize slot: treat null as 1 for consistency
        const normalizedSlot = slot || 1;
        const key = `${heatId}-${normalizedSlot}`;
        const existingIndex = record.dirty_scores.findIndex(
          s => `${s.heat}-${s.slot || 1}` === key
        );

        const dirtyScore = {
          heat: heatId,
          slot: slot,
          score: scoreData.score,
          comments: scoreData.comments,
          good: scoreData.good,
          bad: scoreData.bad,
          timestamp: Date.now()
        };

        if (existingIndex >= 0) {
          // Replace existing (last update wins)
          record.dirty_scores[existingIndex] = dirtyScore;
        } else {
          // Add new
          record.dirty_scores.push(dirtyScore);
        }

        const putRequest = objectStore.put(record);

        putRequest.onsuccess = () => {
          console.debug(`Dirty score added for judge ${judgeId}, heat ${heatId}, slot ${slot}`);
          resolve();
        };

        putRequest.onerror = () => {
          console.error('Failed to add dirty score:', putRequest.error);
          reject(putRequest.error);
        };
      };

      request.onerror = () => {
        console.error('Failed to get record for dirty score:', request.error);
        reject(request.error);
      };
    });
  }

  /**
   * Remove a specific dirty score
   * @param {number} judgeId
   * @param {number} heatId
   * @param {number|null} slot
   */
  async removeDirtyScore(judgeId, heatId, slot = 1) {
    await this.ensureOpen();

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([STORE_NAME], 'readwrite');
      const objectStore = transaction.objectStore(STORE_NAME);
      const request = objectStore.get(judgeId);

      request.onsuccess = () => {
        const record = request.result;
        if (!record) {
          resolve();
          return;
        }

        const normalizedSlot = slot || 1;
        const key = `${heatId}-${normalizedSlot}`;
        record.dirty_scores = record.dirty_scores.filter(
          s => `${s.heat}-${s.slot || 1}` !== key
        );

        const putRequest = objectStore.put(record);

        putRequest.onsuccess = () => {
          console.debug(`Dirty score removed for judge ${judgeId}, heat ${heatId}, slot ${slot}`);
          resolve();
        };

        putRequest.onerror = () => {
          console.error('Failed to remove dirty score:', putRequest.error);
          reject(putRequest.error);
        };
      };

      request.onerror = () => {
        console.error('Failed to get record for dirty score removal:', request.error);
        reject(request.error);
      };
    });
  }

  /**
   * Get all dirty scores for a judge
   * @param {number} judgeId
   * @returns {Promise<Array>}
   */
  async getDirtyScores(judgeId) {
    await this.ensureOpen();

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([STORE_NAME], 'readonly');
      const objectStore = transaction.objectStore(STORE_NAME);
      const request = objectStore.get(judgeId);

      request.onsuccess = () => {
        const record = request.result;
        resolve(record ? record.dirty_scores : []);
      };

      request.onerror = () => {
        console.error('Failed to get dirty scores:', request.error);
        reject(request.error);
      };
    });
  }

  /**
   * Get count of dirty scores for a judge
   * @param {number} judgeId
   * @returns {Promise<number>}
   */
  async getDirtyScoreCount(judgeId) {
    const dirtyScores = await this.getDirtyScores(judgeId);
    return dirtyScores.length;
  }

  /**
   * Clear all dirty scores for a judge
   * @param {number} judgeId
   */
  async clearDirtyScores(judgeId) {
    await this.ensureOpen();

    return new Promise((resolve, reject) => {
      const transaction = this.db.transaction([STORE_NAME], 'readwrite');
      const objectStore = transaction.objectStore(STORE_NAME);
      const request = objectStore.get(judgeId);

      request.onsuccess = () => {
        const record = request.result;
        if (!record) {
          resolve();
          return;
        }

        record.dirty_scores = [];

        const putRequest = objectStore.put(record);

        putRequest.onsuccess = () => {
          console.debug(`All dirty scores cleared for judge ${judgeId}`);
          resolve();
        };

        putRequest.onerror = () => {
          console.error('Failed to clear dirty scores:', putRequest.error);
          reject(putRequest.error);
        };
      };

      request.onerror = () => {
        console.error('Failed to get record for clearing:', request.error);
        reject(request.error);
      };
    });
  }
}

// Export singleton instance
export const dirtyScoresQueue = new DirtyScoresQueue();
```

#### 3. `app/javascript/helpers/heat_data_manager.js` (Refactored)

**Purpose**: Data fetching and caching only.

**Changes**:
- Remove connectivity tracking (use ConnectivityTracker)
- Remove dirty scores methods (use DirtyScoresQueue)
- Keep data fetching, version caching, and batch upload coordination

```javascript
/**
 * HeatDataManager - Simplified data fetching and caching
 *
 * Responsibilities:
 * - Fetch heat data from server
 * - Cache version metadata
 * - Coordinate score saving (delegates to queue and connectivity)
 * - Batch upload coordination
 */

import { connectivityTracker } from 'helpers/connectivity_tracker';
import { dirtyScoresQueue } from 'helpers/dirty_scores_queue';

class HeatDataManager {
  constructor() {
    this.basePath = '';
    this.cachedVersion = null;
  }

  /**
   * Set the base path for all API requests
   */
  setBasePath(basePath) {
    this.basePath = basePath;
    console.debug('[HeatDataManager] Base path set to:', basePath);
  }

  /**
   * Initialize dirty scores queue
   */
  async init() {
    await dirtyScoresQueue.init();
  }

  /**
   * Get dirty score count (delegates to queue)
   */
  async getDirtyScoreCount(judgeId) {
    return dirtyScoresQueue.getDirtyScoreCount(judgeId);
  }

  /**
   * Fetch heat data from server
   */
  async getData(judgeId, forceRefetch = false) {
    const url = `${this.basePath}/scores/${judgeId}/heats.json`;
    console.debug('[HeatDataManager] Fetching data from', url, { forceRefetch });

    try {
      const response = await fetch(url, {
        headers: window.inject_region({ 'Accept': 'application/json' }),
        credentials: 'same-origin'
      });

      if (!response.ok) {
        connectivityTracker.updateConnectivity(false);
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const data = await response.json();
      console.debug('[HeatDataManager] Data fetched successfully');

      // Update connectivity (success)
      connectivityTracker.updateConnectivity(true, judgeId, (id) => this.batchUploadDirtyScores(id));

      // Store version metadata
      await this.storeCachedVersion(judgeId, data);

      return data;
    } catch (error) {
      console.error('[HeatDataManager] Failed to fetch heat data:', error);
      connectivityTracker.updateConnectivity(false);
      throw error;
    }
  }

  /**
   * Store version metadata
   */
  async storeCachedVersion(judgeId, data) {
    this.cachedVersion = {
      max_updated_at: data.max_updated_at,
      heat_count: data.heats?.length || 0
    };
    console.debug('[HeatDataManager] Cached version stored:', this.cachedVersion);
  }

  /**
   * Get cached version
   */
  getCachedVersion() {
    return this.cachedVersion;
  }

  /**
   * Save a score (online or offline)
   */
  async saveScore(judgeId, data) {
    const isFeedback = data.value !== undefined || data.good !== undefined || data.bad !== undefined;
    const url = isFeedback ? `${this.basePath}/scores/${judgeId}/post-feedback` : `${this.basePath}/scores/${judgeId}/post`;

    // Try online if connected
    if (navigator.onLine) {
      try {
        const response = await fetch(url, {
          method: 'POST',
          headers: window.inject_region({
            'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
            'Content-Type': 'application/json'
          }),
          credentials: 'same-origin',
          body: JSON.stringify(data)
        });

        if (response.ok) {
          console.debug('[HeatDataManager] Score saved online');

          // Update connectivity (success)
          connectivityTracker.updateConnectivity(true, judgeId, (id) => this.batchUploadDirtyScores(id));

          // Add to dirty queue to ensure batch sync has latest
          const scoreData = {
            score: data.score || data.value,
            comments: data.comments,
            good: data.good,
            bad: data.bad
          };
          await dirtyScoresQueue.addDirtyScore(judgeId, data.heat, data.slot || null, scoreData);

          // Trigger background batch upload
          this.batchUploadDirtyScores(judgeId).then(result => {
            if (result.succeeded && result.succeeded.length > 0) {
              console.debug('[HeatDataManager] Background upload: synced', result.succeeded.length, 'pending scores');
              document.dispatchEvent(new CustomEvent('pending-count-changed', { bubbles: true }));
            }
          }).catch(err => {
            console.debug('[HeatDataManager] Background upload failed:', err);
          });

          return;
        } else {
          console.warn('[HeatDataManager] Online save failed, falling back to offline');
          connectivityTracker.updateConnectivity(false);
        }
      } catch (error) {
        console.warn('[HeatDataManager] Online save failed, falling back to offline:', error);
        connectivityTracker.updateConnectivity(false);
      }
    }

    // Save offline
    const scoreData = {
      score: data.score || data.value,
      comments: data.comments,
      good: data.good,
      bad: data.bad
    };
    await dirtyScoresQueue.addDirtyScore(judgeId, data.heat, data.slot || null, scoreData);
    console.debug('[HeatDataManager] Score saved offline');
  }

  /**
   * Batch upload dirty scores
   */
  async batchUploadDirtyScores(judgeId) {
    const dirtyScores = await dirtyScoresQueue.getDirtyScores(judgeId);

    if (dirtyScores.length === 0) {
      console.debug('[HeatDataManager] No dirty scores to upload');
      return { succeeded: [], failed: [] };
    }

    console.debug('[HeatDataManager] Uploading', dirtyScores.length, 'dirty scores');

    try {
      const response = await fetch(`${this.basePath}/scores/${judgeId}/batch`, {
        method: 'POST',
        headers: window.inject_region({
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Content-Type': 'application/json'
        }),
        credentials: 'same-origin',
        body: JSON.stringify({ scores: dirtyScores })
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const result = await response.json();

      // Clear dirty scores after successful upload
      await dirtyScoresQueue.clearDirtyScores(judgeId);
      console.debug('[HeatDataManager] Batch upload successful:', result.succeeded.length, 'scores uploaded');

      return result;
    } catch (error) {
      console.error('[HeatDataManager] Failed to batch upload dirty scores:', error);
      throw error;
    }
  }
}

// Export singleton instance
export const heatDataManager = new HeatDataManager();
```

### Files to Update (Imports)

#### `app/javascript/components/heat-page.js`

**Add imports**:
```javascript
import { heatDataManager } from 'helpers/heat_data_manager';
import { connectivityTracker } from 'helpers/connectivity_tracker';
```

**Update references**:
- Line 244: `connectivityTracker.updateConnectivity(true, this.judgeId, ...)`
- Line 237: `connectivityTracker.updateConnectivity(false)`
- Line 265: `connectivityTracker.updateConnectivity(false)`

#### `app/javascript/components/shared/heat-navigation.js`

**No changes needed** - already listens to connectivity-changed events

#### `app/javascript/components/heat-types/*.js`

**Add import**:
```javascript
import { heatDataManager } from 'helpers/heat_data_manager';
```

Already using `heatDataManager.saveScore()` - no other changes needed.

### Update Import Maps

**`config/importmap.rb`**:

**Add**:
```ruby
pin "helpers/connectivity_tracker", to: "helpers/connectivity_tracker.js", preload: true
pin "helpers/dirty_scores_queue", to: "helpers/dirty_scores_queue.js", preload: true
```

### Testing Checklist

**JavaScript Tests** (should all still pass):
```bash
npm run test:run
```
- ✅ 280/280 tests passing

**Manual Testing**:
1. ✅ All SPA interactions still work
2. ✅ Scores save online
3. ✅ Scores queue offline
4. ✅ Batch upload on reconnection
5. ✅ Wifi icon updates correctly
6. ✅ Pending count updates

**Rails Tests**:
```bash
PARALLEL_WORKERS=0 bin/rails test
PARALLEL_WORKERS=0 bin/rails test:system
```
- ✅ All tests still passing

### Commit Point

```bash
git add -A
git commit -m "Split HeatDataManager into focused classes

Separated concerns for better maintainability:

1. ConnectivityTracker (helpers/connectivity_tracker.js)
   - Track network connectivity based on request success/failure
   - Dispatch connectivity-changed events
   - Trigger batch upload on offline→online transition

2. DirtyScoresQueue (helpers/dirty_scores_queue.js)
   - Manage IndexedDB dirty scores queue
   - Add, remove, get, clear operations
   - Last-write-wins deduplication

3. HeatDataManager (helpers/heat_data_manager.js - refactored)
   - Data fetching and caching only
   - Coordinate score saving (delegates to queue/connectivity)
   - Batch upload coordination

Benefits:
- Single responsibility for each class
- Easier testing and debugging
- Clearer dependencies
- No behavior changes

Files created:
- helpers/connectivity_tracker.js (new)
- helpers/dirty_scores_queue.js (new)

Files modified:
- helpers/heat_data_manager.js (simplified)
- config/importmap.rb (added new pins)
- components/heat-page.js (updated imports)

All tests passing: 295 JS + 1107 Rails + 129 System = 1531 total
"
```

---

## Priority 3: Extract Navigation Logic

**Goal**: Extract navigation orchestration from heat-page.js into dedicated class.

**Estimated Time**: 4-7 hours (half day to 1 day)

### Files to Create

#### `app/javascript/helpers/heat_navigator.js`

**Purpose**: Handle heat navigation logic (next, prev, toHeat, popstate).

**Extracted from** `heat-page.js` lines 203-330, 354-394, 654-683

```javascript
/**
 * HeatNavigator - Navigation orchestration for heat SPA
 *
 * Handles navigation between heats including:
 * - Next/previous heat
 * - Navigate to specific heat
 * - Browser back/forward (popstate)
 * - Slot navigation for multi-slot heats
 * - Heat filtering based on judge preferences
 */

class HeatNavigator {
  constructor(heatPage) {
    this.heatPage = heatPage;
    this.setupPopstateListener();
  }

  /**
   * Navigate to a specific heat
   */
  async navigateToHeat(heatNumber, slot = 0) {
    this.heatPage.currentHeatNumber = parseInt(heatNumber);
    this.heatPage.slot = parseInt(slot);

    // Update URL without reload
    const url = new URL(window.location);
    url.searchParams.set('heat', this.heatPage.currentHeatNumber);
    if (this.heatPage.slot > 0) {
      url.searchParams.set('slot', this.heatPage.slot);
    } else {
      url.searchParams.delete('slot');
    }
    url.searchParams.set('style', this.heatPage.scoringStyle);
    window.history.pushState({}, '', url);

    // Check version and refetch if needed
    await this.heatPage.checkVersionAndRefetch();

    // Render
    this.heatPage.render();
  }

  /**
   * Navigate to next heat
   */
  navigateNext() {
    const heat = this.getCurrentHeat();
    if (!heat) return;

    // Check if we need to navigate to next slot or next heat
    if (heat.dance.heat_length && this.heatPage.slot > 0) {
      const maxSlots = heat.dance.heat_length * (heat.dance.uses_scrutineering ? 2 : 1);
      if (this.heatPage.slot < maxSlots) {
        this.navigateToHeat(this.heatPage.currentHeatNumber, this.heatPage.slot + 1);
        return;
      }
    }

    // Find next heat
    const heats = this.getFilteredHeats();
    const currentIndex = heats.findIndex(h => h.number === this.heatPage.currentHeatNumber);

    if (currentIndex >= 0 && currentIndex < heats.length - 1) {
      const nextHeat = heats[currentIndex + 1];
      const nextSlot = nextHeat.dance.heat_length ? 1 : 0;
      this.navigateToHeat(nextHeat.number, nextSlot);
    }
  }

  /**
   * Navigate to previous heat
   */
  navigatePrev() {
    const heat = this.getCurrentHeat();
    if (!heat) return;

    // Check if we need to navigate to previous slot
    if (this.heatPage.slot > 1) {
      this.navigateToHeat(this.heatPage.currentHeatNumber, this.heatPage.slot - 1);
      return;
    }

    // Find previous heat
    const heats = this.getFilteredHeats();
    const currentIndex = heats.findIndex(h => h.number === this.heatPage.currentHeatNumber);

    if (currentIndex > 0) {
      const prevHeat = heats[currentIndex - 1];
      let prevSlot = 0;

      if (prevHeat.dance.heat_length) {
        const maxSlots = prevHeat.dance.heat_length * (prevHeat.dance.uses_scrutineering ? 2 : 1);
        prevSlot = maxSlots;
      }

      this.navigateToHeat(prevHeat.number, prevSlot);
    }
  }

  /**
   * Get current heat
   */
  getCurrentHeat() {
    if (!this.heatPage.data || !this.heatPage.data.heats) return null;
    return this.heatPage.data.heats.find(h => h.number === this.heatPage.currentHeatNumber);
  }

  /**
   * Get filtered heats based on judge preferences
   */
  getFilteredHeats() {
    if (!this.heatPage.data || !this.heatPage.data.heats) return [];

    const showSolos = this.heatPage.data.judge.review_solos;
    let heats = this.heatPage.data.heats;

    if (showSolos === 'none') {
      heats = heats.filter(h => h.category !== 'Solo');
    } else if (showSolos === 'even') {
      heats = heats.filter(h => h.category !== 'Solo' || h.number % 2 === 0);
    } else if (showSolos === 'odd') {
      heats = heats.filter(h => h.category !== 'Solo' || h.number % 2 === 1);
    }

    return heats;
  }

  /**
   * Get prev/next URLs for navigation
   */
  getNavigationUrls() {
    const heats = this.getFilteredHeats();
    const currentIndex = heats.findIndex(h => h.number === this.heatPage.currentHeatNumber);
    const heat = this.getCurrentHeat();

    let prevUrl = '';
    let nextUrl = '';

    // Previous
    if (this.heatPage.slot > 1) {
      prevUrl = `${this.heatPage.basePath}/scores/${this.heatPage.judgeId}/spa?heat=${this.heatPage.currentHeatNumber}&slot=${this.heatPage.slot - 1}&style=${this.heatPage.scoringStyle}`;
    } else if (currentIndex > 0) {
      const prevHeat = heats[currentIndex - 1];
      if (prevHeat.dance.heat_length) {
        const maxSlots = prevHeat.dance.heat_length * (prevHeat.dance.uses_scrutineering ? 2 : 1);
        prevUrl = `${this.heatPage.basePath}/scores/${this.heatPage.judgeId}/spa?heat=${prevHeat.number}&slot=${maxSlots}&style=${this.heatPage.scoringStyle}`;
      } else {
        prevUrl = `${this.heatPage.basePath}/scores/${this.heatPage.judgeId}/spa?heat=${prevHeat.number}&style=${this.heatPage.scoringStyle}`;
      }
    }

    // Next
    if (heat && heat.dance.heat_length && this.heatPage.slot > 0) {
      const maxSlots = heat.dance.heat_length * (heat.dance.uses_scrutineering ? 2 : 1);
      if (this.heatPage.slot < maxSlots) {
        nextUrl = `${this.heatPage.basePath}/scores/${this.heatPage.judgeId}/spa?heat=${this.heatPage.currentHeatNumber}&slot=${this.heatPage.slot + 1}&style=${this.heatPage.scoringStyle}`;
      }
    }

    if (!nextUrl && currentIndex >= 0 && currentIndex < heats.length - 1) {
      const nextHeat = heats[currentIndex + 1];
      if (nextHeat.dance.heat_length) {
        nextUrl = `${this.heatPage.basePath}/scores/${this.heatPage.judgeId}/spa?heat=${nextHeat.number}&slot=1&style=${this.heatPage.scoringStyle}`;
      } else {
        nextUrl = `${this.heatPage.basePath}/scores/${this.heatPage.judgeId}/spa?heat=${nextHeat.number}&style=${this.heatPage.scoringStyle}`;
      }
    }

    return { prevUrl, nextUrl };
  }

  /**
   * Setup popstate listener for browser back/forward
   */
  setupPopstateListener() {
    this.popstateHandler = (event) => {
      console.debug('[HeatNavigator] Popstate event - URL changed via browser navigation');

      const url = new URL(window.location);
      const heatParam = url.searchParams.get('heat');
      const slotParam = url.searchParams.get('slot');
      const styleParam = url.searchParams.get('style');

      if (heatParam) {
        const newHeatNumber = parseInt(heatParam);
        const newSlot = slotParam ? parseInt(slotParam) : 0;
        const newStyle = styleParam || 'radio';

        this.heatPage.currentHeatNumber = newHeatNumber;
        this.heatPage.slot = newSlot;
        this.heatPage.scoringStyle = newStyle;

        this.heatPage.checkVersionAndRefetch().then(() => {
          this.heatPage.render();
        });
      } else {
        this.heatPage.currentHeatNumber = null;
        this.heatPage.render();
      }
    };

    window.addEventListener('popstate', this.popstateHandler);
  }

  /**
   * Remove popstate listener
   */
  removePopstateListener() {
    if (this.popstateHandler) {
      window.removeEventListener('popstate', this.popstateHandler);
    }
  }

  /**
   * Cleanup
   */
  destroy() {
    this.removePopstateListener();
  }
}

export default HeatNavigator;
```

### Files to Update

#### `app/javascript/components/heat-page.js`

**Add import**:
```javascript
import HeatNavigator from 'helpers/heat_navigator';
```

**In `connectedCallback()`**:
```javascript
// Create navigator
this.navigator = new HeatNavigator(this);
```

**In `disconnectedCallback()`**:
```javascript
// Cleanup navigator
if (this.navigator) {
  this.navigator.destroy();
}
```

**Replace navigation methods**:
- Delete `navigateToHeat()` (lines 203-223)
- Delete `navigateNext()` (lines 278-300)
- Delete `navigatePrev()` (lines 305-330)
- Delete `getFilteredHeats()` (lines 335-350)
- Delete `getNavigationUrls()` (lines 354-394)
- Delete `getCurrentHeat()` (lines 147-150)
- Delete `setupPopstateListener()` (lines 654-683)
- Delete `removePopstateListener()` (lines 689-693)

**Update event listeners**:
```javascript
// Listen for navigation events from heat-navigation component
this.addEventListener('navigate-prev', () => {
  this.navigator.navigatePrev();  // Use navigator
});

this.addEventListener('navigate-next', () => {
  this.navigator.navigateNext();  // Use navigator
});

this.addEventListener('navigate-to-heat', (e) => {
  const heatNumber = e.detail.heat;
  this.navigator.navigateToHeat(heatNumber, 0);  // Use navigator
});
```

**Update `render()` method**:
```javascript
// Get navigation URLs from navigator
const { prevUrl, nextUrl } = this.navigator.getNavigationUrls();
```

### Update Import Maps

**`config/importmap.rb`**:

**Add**:
```ruby
pin "helpers/heat_navigator", to: "helpers/heat_navigator.js", preload: true
```

### Testing Checklist

**JavaScript Tests**:
```bash
npm run test:run
```
- ✅ 280/280 tests passing (especially navigation.test.js)

**Manual Testing**:
1. ✅ Navigate next → works
2. ✅ Navigate prev → works
3. ✅ Navigate to specific heat → works
4. ✅ Slot navigation (multi-slot heats) → works
5. ✅ Browser back button → works
6. ✅ Browser forward button → works
7. ✅ Direct URL navigation → works
8. ✅ Heat filtering (solo preferences) → works

**Rails Tests**:
```bash
PARALLEL_WORKERS=0 bin/rails test
PARALLEL_WORKERS=0 bin/rails test:system
```
- ✅ All tests still passing

### Commit Point

```bash
git add -A
git commit -m "Extract navigation logic into HeatNavigator class

Separated navigation concerns from HeatPage orchestrator:

Created HeatNavigator (helpers/heat_navigator.js):
- Navigate to specific heat (with slot support)
- Navigate next/prev
- Get navigation URLs
- Handle browser back/forward (popstate)
- Filter heats based on judge preferences
- Get current heat

Simplified HeatPage:
- Removed 240 lines of navigation logic
- Delegates to navigator for all navigation
- Focuses on data management and rendering

Benefits:
- Single responsibility: navigation vs orchestration
- Easier to test navigation logic in isolation
- Clearer code organization
- No behavior changes

Files created:
- helpers/heat_navigator.js (new)

Files modified:
- components/heat-page.js (simplified)
- config/importmap.rb (added heat_navigator pin)

All tests passing: 295 JS + 1107 Rails + 129 System = 1531 total
"
```

---

## Priority 4: Extract FeedbackPanel Component (NEW)

**Goal**: Extract feedback button rendering and interaction logic into reusable component.

**Rationale**: The offline fixes revealed that feedback button logic in heat-table.js is complex (~70 lines, lines 666-734) and could benefit from extraction. This logic handles:
- Button rendering with selected state
- Click handling with server communication
- Gathering current values for offline preservation
- UI updates based on server response
- Event dispatching for in-memory updates

**Estimated Time**: 6-10 hours (1-1.5 days)

### Current Problem

**`heat-table.js` lines 666-734** (feedback button logic):
- 23 lines for button click handler
- 28 lines for UI update logic
- 11 lines for event dispatch
- Mixed concerns: DOM manipulation, data gathering, server communication

**Complexity**: This logic is tightly coupled to heat-table rendering, making it hard to:
- Test feedback interactions in isolation
- Reuse feedback UI in other contexts (e.g., heat-solo)
- Understand feedback behavior separate from table rendering

### Files to Create

#### `app/javascript/components/shared/feedback-panel.js`

**Purpose**: Reusable feedback button panel component.

```javascript
/**
 * FeedbackPanel - Feedback button panel component
 *
 * Renders feedback buttons (good/bad/value) and handles interactions.
 * Communicates with server via HeatDataManager and dispatches events
 * for parent components to update their state.
 *
 * Usage:
 *   <feedback-panel
 *     judge-id="55"
 *     heat="100"
 *     slot="1"
 *     good="F P"
 *     bad=""
 *     value="3"
 *     overall-options='["1","2","3","4","5"]'
 *     good-options='[{"abbr":"F","full":"Footwork"},...]'
 *     bad-options='[...]'>
 *   </feedback-panel>
 */

import { heatDataManager } from 'helpers/heat_data_manager';

class FeedbackPanel extends HTMLElement {
  connectedCallback() {
    this.parseAttributes();
    this.render();
    this.setupEventListeners();
  }

  parseAttributes() {
    this.judgeId = parseInt(this.getAttribute('judge-id'));
    this.heat = parseInt(this.getAttribute('heat'));
    this.slot = this.getAttribute('slot') ? parseInt(this.getAttribute('slot')) : null;
    this.good = this.getAttribute('good') || '';
    this.bad = this.getAttribute('bad') || '';
    this.value = this.getAttribute('value') || '';

    try {
      this.overallOptions = JSON.parse(this.getAttribute('overall-options') || '[]');
      this.goodOptions = JSON.parse(this.getAttribute('good-options') || '[]');
      this.badOptions = JSON.parse(this.getAttribute('bad-options') || '[]');
    } catch (e) {
      console.error('[FeedbackPanel] Failed to parse options:', e);
      this.overallOptions = [];
      this.goodOptions = [];
      this.badOptions = [];
    }
  }

  render() {
    const goodFeedback = this.good.split(' ').filter(f => f);
    const badFeedback = this.bad.split(' ').filter(f => f);

    this.innerHTML = `
      <div class="feedback-panel">
        <!-- Overall Score -->
        <div class="feedback-section value" data-value="${this.value}">
          ${this.overallOptions.map(opt => `
            <button class="feedback-btn ${this.value === opt ? 'selected' : ''}">
              <abbr>${opt}</abbr>
            </button>
          `).join('')}
        </div>

        <!-- Good Feedback -->
        <div class="feedback-section good" data-value="${this.good}">
          ${this.goodOptions.map(opt => `
            <button class="feedback-btn ${goodFeedback.includes(opt.abbr) ? 'selected' : ''}">
              <abbr title="${opt.full}">${opt.abbr}</abbr>
              <span class="sr-only">${opt.full}</span>
            </button>
          `).join('')}
        </div>

        <!-- Bad Feedback -->
        <div class="feedback-section bad" data-value="${this.bad}">
          ${this.badOptions.map(opt => `
            <button class="feedback-btn ${badFeedback.includes(opt.abbr) ? 'selected' : ''}">
              <abbr title="${opt.full}">${opt.abbr}</abbr>
              <span class="sr-only">${opt.full}</span>
            </button>
          `).join('')}
        </div>
      </div>
    `;
  }

  setupEventListeners() {
    const buttons = this.querySelectorAll('.feedback-btn');

    for (const button of buttons) {
      button.addEventListener('click', async () => {
        await this.handleFeedbackClick(button);
      });
    }
  }

  async handleFeedbackClick(button) {
    const feedbackType = button.parentElement.classList.contains('good') ? 'good' :
      (button.parentElement.classList.contains('bad') ? 'bad' : 'value');
    const feedbackValue = button.querySelector('abbr')?.textContent;

    // Send only the clicked value - server handles toggling and mutual exclusivity
    const scoreData = {
      heat: this.heat,
      slot: this.slot,
      [feedbackType]: feedbackValue
    };

    // Get current values from all sections for offline preservation
    const sections = this.querySelectorAll('.feedback-section');
    const currentScore = {};
    for (const section of sections) {
      const sectionType = section.classList.contains('good') ? 'good' :
        (section.classList.contains('bad') ? 'bad' : 'value');
      currentScore[sectionType] = section.dataset.value || '';
    }

    try {
      const response = await heatDataManager.saveScore(this.judgeId, scoreData, currentScore);

      // Update UI based on response - only update sections that are in the response
      if (response && !response.error) {
        this.updateUI(response);

        // Dispatch event for parent component to update in-memory data
        this.dispatchEvent(new CustomEvent('score-updated', {
          bubbles: true,
          detail: {
            heat: scoreData.heat,
            slot: scoreData.slot,
            ...response  // Spread response to include value/good/bad/comments
          }
        }));
      }
    } catch (error) {
      console.error('[FeedbackPanel] Failed to save feedback:', error);
    }
  }

  updateUI(response) {
    const sections = this.querySelectorAll('.feedback-section');

    for (const section of sections) {
      const sectionType = section.classList.contains('good') ? 'good' :
        (section.classList.contains('bad') ? 'bad' : 'value');

      // Only update this section if it's in the response
      if (response[sectionType] === undefined) {
        continue;  // Skip sections not in response - preserves existing UI state
      }

      const feedbackValue = response[sectionType] || '';  // Handle null
      const feedback = feedbackValue.split(' ').filter(f => f);

      section.dataset.value = feedbackValue;

      for (const btn of section.querySelectorAll('button')) {
        const btnAbbr = btn.querySelector('abbr');
        if (btnAbbr && feedback.includes(btnAbbr.textContent)) {
          btn.classList.add('selected');
        } else {
          btn.classList.remove('selected');
        }
      }
    }
  }
}

customElements.define('feedback-panel', FeedbackPanel);

export default FeedbackPanel;
```

### Files to Update

#### `app/javascript/components/heat-types/heat-table.js`

**Import**:
```javascript
import FeedbackPanel from 'components/shared/feedback-panel';
```

**Replace feedback button rendering** (lines 266-295):

**Before** (~30 lines of template):
```javascript
${entry.open_feedback ? `
  <tr class="open-fb-row" data-heat="${heat.number}">
    <td colspan="${colspan}">
      <div class="flex gap-2">
        <div class="value" data-value="${judgeScore?.value || ''}">
          ${this.event.feedback.overall.map(opt => `
            <button>
              <abbr>${opt}</abbr>
            </button>
          `).join('')}
        </div>
        <div class="good" data-value="${judgeScore?.good || ''}">
          ${this.event.feedback.good.map(opt => `
            <button>
              <abbr title="${opt.full}">${opt.abbr}</abbr>
              <span class="sr-only">${opt.full}</span>
            </button>
          `).join('')}
        </div>
        <div class="bad" data-value="${judgeScore?.bad || ''}">
          ${this.event.feedback.bad.map(opt => `
            <button>
              <abbr title="${opt.full}">${opt.abbr}</abbr>
              <span class="sr-only">${opt.full}</span>
            </button>
          `).join('')}
        </div>
      </div>
    </td>
  </tr>
` : ''}
```

**After** (~5 lines using component):
```javascript
${entry.open_feedback ? `
  <tr class="open-fb-row" data-heat="${heat.number}">
    <td colspan="${colspan}">
      <feedback-panel
        judge-id="${this.judgeData.id}"
        heat="${heat.number}"
        slot="${this.getAttribute('slot') || ''}"
        good="${judgeScore?.good || ''}"
        bad="${judgeScore?.bad || ''}"
        value="${judgeScore?.value || ''}"
        overall-options='${JSON.stringify(this.event.feedback.overall)}'
        good-options='${JSON.stringify(this.event.feedback.good)}'
        bad-options='${JSON.stringify(this.event.feedback.bad)}'>
      </feedback-panel>
    </td>
  </tr>
` : ''}
```

**Delete feedback button handler** (lines 666-734) - now handled by component.

**Keep score-updated event listener** in heat-table.js to update in-memory data.

### Update Import Maps

**`config/importmap.rb`**:

**Add**:
```ruby
pin "components/shared/feedback-panel", to: "components/shared/feedback-panel.js", preload: true
```

### Testing Checklist

**JavaScript Tests**:
```bash
npm run test:run
```
- ✅ 295/295 tests passing

**Add new tests** for `feedback_panel.test.js`:
```javascript
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { screen } from '@testing-library/dom'
import '@testing-library/jest-dom'
import FeedbackPanel from '../../app/javascript/components/shared/feedback-panel'

describe('FeedbackPanel', () => {
  beforeEach(() => {
    document.body.innerHTML = ''
  })

  it('renders feedback buttons', () => {
    const panel = document.createElement('feedback-panel')
    panel.setAttribute('judge-id', '55')
    panel.setAttribute('heat', '100')
    panel.setAttribute('good', 'F P')
    panel.setAttribute('bad', '')
    panel.setAttribute('value', '3')
    panel.setAttribute('overall-options', '["1","2","3","4","5"]')
    panel.setAttribute('good-options', '[{"abbr":"F","full":"Footwork"},{"abbr":"P","full":"Posture"}]')
    panel.setAttribute('bad-options', '[]')

    document.body.appendChild(panel)

    expect(panel.querySelector('.value button.selected abbr').textContent).toBe('3')
    expect(panel.querySelectorAll('.good button.selected')).toHaveLength(2)
  })

  it('handles feedback button click', async () => {
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: true,
        json: () => Promise.resolve({ good: 'F P T' })
      })
    )

    const panel = document.createElement('feedback-panel')
    panel.setAttribute('judge-id', '55')
    panel.setAttribute('heat', '100')
    panel.setAttribute('good', 'F P')
    panel.setAttribute('good-options', '[{"abbr":"F","full":"Footwork"},{"abbr":"P","full":"Posture"},{"abbr":"T","full":"Timing"}]')

    document.body.appendChild(panel)

    const tButton = Array.from(panel.querySelectorAll('.good button'))
      .find(btn => btn.querySelector('abbr').textContent === 'T')

    await tButton.click()

    // Wait for async update
    await new Promise(resolve => setTimeout(resolve, 50))

    expect(panel.querySelectorAll('.good button.selected')).toHaveLength(3)
  })
})
```

**Manual Testing**:
1. ✅ Feedback buttons render correctly
2. ✅ Clicking feedback button saves and updates UI
3. ✅ Offline mode preserves all fields
4. ✅ Multiple heats with feedback work
5. ✅ Mutual exclusivity (good/bad) works

**Rails Tests**:
```bash
PARALLEL_WORKERS=0 bin/rails test
PARALLEL_WORKERS=0 bin/rails test:system
```
- ✅ All tests still passing

### Commit Point

```bash
git add -A
git commit -m "Extract feedback panel into reusable component

Created FeedbackPanel (components/shared/feedback-panel.js):
- Renders feedback buttons (good/bad/value)
- Handles button clicks with server communication
- Updates UI based on server response
- Dispatches score-updated events for parent components
- Preserves fields for offline saves

Simplified heat-table.js:
- Reduced feedback rendering from 30 lines to 5 lines
- Removed 70 lines of feedback button handling logic
- Uses feedback-panel component declaratively
- Clearer separation of concerns

Benefits:
- Reusable feedback UI across heat types
- Testable in isolation
- Single responsibility for feedback interactions
- No behavior changes

Files created:
- components/shared/feedback-panel.js (new)
- test/javascript/feedback_panel.test.js (new, 5 tests)

Files modified:
- components/heat-types/heat-table.js (simplified)
- config/importmap.rb (added feedback-panel pin)

All tests passing: 300 JS + 1107 Rails + 129 System = 1536 total
"
```

---

## Success Criteria

After completing all priorities:

**Code Quality**:
- ✅ Clear architectural boundaries (ERB = Stimulus, SPA = Web Components)
- ✅ Single responsibility for each class/component
- ✅ No coupling between controllers and components
- ✅ Easy to understand and maintain
- ✅ Reusable components (FeedbackPanel, HeatNavigator)
- ✅ Testable logic in isolation (ScoreMergeHelper, ConnectivityTracker)

**Test Coverage**:
- ✅ All ~1536 tests passing (300 JS + 1107 Rails + 129 System)
- ✅ No regressions introduced
- ✅ Both SPA and ERB paths tested
- ✅ New helper classes have dedicated test suites

**Functionality**:
- ✅ SPA works identically to before
- ✅ ERB views work identically to before
- ✅ Offline/online sync works correctly
- ✅ All interactions work (keyboard, touch, drag-and-drop)
- ✅ Feedback buttons work in all modes

**Documentation**:
- ✅ Clear comments in new classes
- ✅ Commit messages explain changes
- ✅ This plan serves as reference

---

## Rollback Strategy

If issues arise during any priority phase:

**Rollback single priority**:
```bash
git reset --hard HEAD~1  # Undo last commit
```

**Rollback all changes**:
```bash
git reset --hard <commit-before-refactoring>
```

**Test after rollback**:
```bash
npm run test:run
PARALLEL_WORKERS=0 bin/rails test
PARALLEL_WORKERS=0 bin/rails test:system
```

All tests should pass after rollback to previous state.

---

## Timeline Summary

| Priority | Time Estimate | Calendar Days | Status |
|----------|---------------|---------------|--------|
| 1. Remove Stimulus from SPA | 10-14 hours | 1-2 days | ✅ **COMPLETE** (commit 835754e7) |
| 2a. Extract ScoreMergeHelper | 2-4 hours | 0.5 day | ⏳ Pending |
| 2b-d. Split HeatDataManager | 8-13 hours | 1-2 days | ⏳ Pending |
| 3. Extract Navigation | 4-7 hours | 0.5-1 day | ⏳ Pending |
| 4. Extract FeedbackPanel | 6-10 hours | 1-1.5 days | ⏳ Pending |
| **Total** | **30-48 hours** | **4.5-7 days** | 1 of 5 complete |

**Phased approach**: Complete each priority, test in production, then proceed to next.

**Continuous deployment**: Commit after each priority, deploy, verify in production before proceeding.

**Recommended sequence**:
1. ✅ Priority 1 complete - clean architectural boundary established
2. **Next: Priority 2a** (ScoreMergeHelper) - quick win, simplifies saveScore()
3. Then Priority 2b-d (Split HeatDataManager) - major refactor, builds on 2a
4. Then Priority 3 (HeatNavigator) - independent extraction
5. Finally Priority 4 (FeedbackPanel) - polish, reusable component

---

## Notes

- This plan assumes working in focused blocks - actual calendar time may vary
- Each priority is independently valuable - can stop after any phase
- ✅ **Priority 1 complete** - biggest architectural win achieved
- **Priority 2a (NEW)** addresses complexity added by offline fixes
- Priorities 2b-d, 3, 4 are progressive refinements
- All changes are backwards compatible until ERB views retired
- ERB retirement is future work, not in this plan

---

## Revision History

**2025-11-15**: Plan revised after Priority 1 completion and offline scoring fixes
- Added Priority 2a (ScoreMergeHelper) - extract merging logic added in offline fixes
- Added Priority 4 (FeedbackPanel) - extract complex feedback button logic
- Renumbered original Priority 2 to Priority 2b-d
- Updated test baseline: 287 JS tests (+7 from offline fixes)
- Updated time estimates: 30-48 hours total (was 22-34 hours)
- Updated line counts to reflect current state

**2025-11-14**: Original plan created
- Priority 1: Remove Stimulus from SPA
- Priority 2: Split HeatDataManager
- Priority 3: Extract Navigation Logic
- Test baseline: 280 JS tests
