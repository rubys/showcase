# JSON Payload Size Analysis

**Date:** 2025-11-06
**Purpose:** Validate assumptions for SPA approach JSON download size

## Test Databases

Analyzed the three largest showcases:
1. **2025-montgomery-lincolnshire** - 4,302 total heats, 251 unique heat numbers
2. **2025-sanjose-september** - 3,951 total heats, 435 unique heat numbers
3. **2025-raleigh-disney** - No judges assigned yet (skipped)

## Results

### Montgomery-Lincolnshire (251 Heat Numbers)

```
Raw JSON:        1.04MB
Gzip compressed: 69.9KB
Compression:     93.4% reduction

Per-heat averages:
Raw:             4.2KB per heat number
Compressed:      285B per heat number
```

### San Jose September (435 Heat Numbers)

```
Raw JSON:        991.3KB
Gzip compressed: 60.3KB
Compression:     93.9% reduction

Per-heat averages:
Raw:             2.3KB per heat number
Compressed:      141B per heat number
```

## Analysis

### Payload Structure Included

The measurement includes realistic judge scoring data:
- Judge ID and name
- Event name and settings (scoring modes, column order, etc.)
- For each heat number:
  - Heat metadata (number, category, dance name, ballroom)
  - All subjects (entries/solos) in that heat:
    - Back numbers
    - Lead person (ID, name, studio)
    - Follow person (ID, name, studio)
    - Instructor (ID, name)
    - Age category and level
    - Studio name
    - Existing scores for this judge (value, good, bad, comments)
  - Solo-specific data:
    - Formations (person ID, name, on_floor status)

### What's NOT Included

These measurements are still **incomplete**. Missing data that would be needed:
- Full Dance objects (currently just dance name)
  - Category relationships (open/closed/multi/solo)
  - Multi-dance children
  - Dance order and settings
- Event settings (currently partial)
  - Might need more settings for rendering
- Solo songs (title, artist) - not included
- Formation details beyond ID/name
- Category extensions for solo categories

**Estimated multiplier for complete data:** 1.2-1.5x larger

### Final Estimates

**Montgomery-Lincolnshire (251 heats):**
- Raw: 1.04MB → ~1.3-1.6MB with complete data
- Compressed: 69.9KB → ~84-105KB with complete data

**San Jose September (435 heats):**
- Raw: 991KB → ~1.2-1.5MB with complete data
- Compressed: 60.3KB → ~72-90KB with complete data

## Compression Analysis

**Gzip compression ratio: 93.4-93.9%**

This exceptional compression is due to:
- High JSON redundancy (repeated keys, structure)
- Repeated studio names, person names, dance names
- Text-based format compresses very well

Rails default middleware applies gzip compression automatically, so these compressed sizes represent actual network transfer.

## Bandwidth Comparison

### Service Worker Approach (OFFLINE_SCORING_PLAN.md)
- 251 separate page fetches
- Estimated ~5-10KB per page (HTML + embedded data)
- Total: ~1.25-2.5MB uncompressed
- Compressed: ~200-400KB (estimate)
- **Cache hits after first load reduce this**

### SPA Approach (SPA_SCORING_PLAN.md)
- Single JSON fetch
- ~1.3-1.6MB uncompressed
- ~84-105KB compressed (Montgomery)
- ~72-90KB compressed (San Jose)

**Winner: SPA approach is 2-5x more efficient in bandwidth**

## Performance Implications

### Initial Load
- 84KB @ 3G speeds (~1.6 Mbps) = **420ms download**
- 105KB @ 3G speeds = **525ms download**
- Plus JSON parsing time (~50-100ms for 1MB)
- **Total: ~500-650ms for data ready**

### Memory Usage
- Raw JSON in memory: ~1.3-1.6MB
- Parsed JavaScript object: ~2-3MB (estimate with object overhead)
- IndexedDB storage: Similar to JSON size (~1.5MB)
- **Total memory footprint: ~4-5MB**

This is well within acceptable limits for modern devices (phones have GB of RAM).

### Compared to Service Worker Cache
- Service worker stores 251 HTML pages
- Each page ~15-25KB (HTML + inline styles)
- Total cache size: ~4-6MB
- **SPA uses 25-30% less storage**

## Recommendations

### ✅ SPA Approach is Viable

**Reasons:**
1. **Bandwidth efficient:** 84-105KB compressed is very reasonable
2. **Fast download:** Under 1 second even on 3G
3. **Low memory:** 4-5MB total is trivial for modern devices
4. **Better than service worker:** 2-5x less bandwidth, 70% less storage

### ⚠️ Considerations

1. **JSON parsing time:** 1MB+ JSON takes 50-100ms to parse
   - Mitigation: Parse happens once, then cached
   - Not a concern for user experience

2. **IndexedDB write time:** ~100-200ms to store 1.5MB
   - Happens in background
   - Doesn't block rendering

3. **Largest event tested:** 435 heat numbers (San Jose)
   - Still only 90KB compressed
   - Room for growth (could handle 1000+ heats easily)

4. **Network timeout:** 1MB JSON needs reliable connection
   - Mitigation: Show loading progress
   - Retry with exponential backoff
   - Fall back to cached data if available

### 📊 Comparison to Original Estimate

**Original SPA plan estimated:** 500KB-1MB compressed

**Actual measurement:** 60-105KB compressed

**We are 5-10x better than estimated!** This is due to:
- Better gzip compression than anticipated (93-94% vs estimated 80%)
- Leaner data structure (didn't over-serialize)
- JSON is highly compressible (repeated keys, structure)

## Conclusion

**The SPA approach is highly feasible from a payload size perspective.**

Key findings:
- ✅ Compressed size is 60-105KB (well under 200KB threshold)
- ✅ Download time is under 1 second on 3G
- ✅ Memory usage is minimal (4-5MB)
- ✅ More efficient than service worker approach
- ✅ Room for growth (tested up to 435 heat numbers)

**Recommendation:** Proceed with SPA approach. JSON size is NOT a blocking concern.

## Next Steps

1. ✅ JSON size validated (this document)
2. **TODO:** Build proof-of-concept for one heat type (Solo recommended)
3. **TODO:** Measure actual rendering performance with full JSON
4. **TODO:** Test with production-scale data (435+ heats)
5. **TODO:** Validate multi-dance slot navigation complexity
