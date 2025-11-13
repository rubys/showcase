# Phase 7: Manual Testing Checklist

## Offline Sync Testing (CRITICAL - Cannot be fully automated)

### Test 1: Offline Queue and Sync
**Setup:**
1. Open Chrome DevTools (F12)
2. Go to Network tab
3. Check "Offline" checkbox at top

**Steps:**
1. Visit `/scores/{judge_id}/spa`
2. Score 5 different heats (click radio buttons, make selections)
3. Verify scores appear selected in UI
4. Check Application > IndexedDB > showcase > dirty_scores
   - Should see 5 entries
5. Uncheck "Offline" in DevTools
6. Navigate to a different heat
7. Check dirty_scores again - should be empty (synced)
8. Verify scores in database: `Score.where(judge_id: {judge_id}).count` should be 5

**Expected:** All 5 scores sync to database when going online

---

### Test 2: Offline Edit Overwrites Online Score
**Steps:**
1. Score heat #10 while online (select "1")
2. Verify in database: `Score.find_by(heat_id: heat_10.id).value` == "1"
3. Go offline (DevTools Network > Offline)
4. Change score to "2"
5. Go online
6. Navigate to another heat to trigger sync
7. Check database again

**Expected:** Score should be "2" (offline edit overwrites)

---

### Test 3: IndexedDB Persists Across Page Reload
**Steps:**
1. Go offline
2. Score 3 heats
3. Close browser tab completely
4. Reopen `/scores/{judge_id}/spa` in new tab
5. Navigate to the 3 heats you scored

**Expected:** All 3 scores still visible (loaded from IndexedDB)

---

## Performance Testing

### Test 4: Large Heat (50+ couples)
**Setup:** Create heat with 50+ couples

**Steps:**
1. Open heat in cards view
2. Drag several cards between score columns
3. Measure responsiveness

**Expected:** No noticeable lag, smooth dragging

---

### Test 5: Concurrent Multi-Judge Scoring
**Setup:** Two judges, same event

**Steps:**
1. Open Judge A in one browser
2. Open Judge B in another browser (or incognito)
3. Both score different heats simultaneously
4. Check database

**Expected:** Both sets of scores saved correctly, no conflicts

---

## Browser Compatibility

### Test 6: Safari Testing
**Steps:** Repeat Tests 1-3 in Safari

**Known Issue:** IndexedDB support varies

---

### Test 7: iPad Testing
**Steps:** Repeat Tests 1-3 on iPad Safari

**Expected:** Touch interactions work, offline mode works

---

## Edge Cases

### Test 8: Network Interruption During Sync
**Steps:**
1. Score 10 heats while offline
2. Go online
3. Navigate to trigger sync
4. Immediately go offline again (before all 10 sync)
5. Go online again

**Expected:** Remaining scores resume syncing

---

### Test 9: Duplicate Score Prevention
**Steps:**
1. Score heat #5 offline
2. Before syncing, score heat #5 again (change value)
3. Go online

**Expected:** Only latest value syncs (no duplicate scores)

---

## Automated Tests (Simplified)

The following 3 tests in `test/system/spa_offline_test.rb` provide basic smoke tests:
1. SPA loads and components render
2. Scoring interface is interactive
3. Navigation works between heats

**Note:** Full offline testing requires manual testing with DevTools Network panel.
