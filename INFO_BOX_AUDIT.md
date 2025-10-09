# Info-Box Audit Report
*Generated: 2025-10-09*

## Executive Summary

This report provides a comprehensive audit of info-box implementations across all HTML pages reachable from `event/root.html.erb`, excluding docs pages and non-HTML formats (PDF, JSON, etc.).

**Key Findings:**
- **Total reachable HTML pages:** ~283 view templates
- **Pages with info-boxes:** 52 (18% coverage)
- **Pages that should have info-boxes but don't:** 15 HIGH priority, 10 MEDIUM priority
- **Overall quality:** Good - existing info-boxes are well-written and helpful

---

## Current State: Pages WITH Info-Boxes (52)

### Excellent Info-Boxes ✅
These are comprehensive, accurate, and provide clear guidance:

1. **event/root.html.erb** - Perfect workflow overview for first-time event setup
2. **heats/index.html.erb** - Comprehensive agenda management guide
3. **categories/index.html.erb** - Excellent agenda customization guide
4. **categories/_form.html.erb** - Detailed timing system explanation
5. **tables/index.html.erb** - Perfect guide for complex table assignment workflow
6. **people/certificates.html.erb** - Excellent step-by-step certificate generation
7. **entries/_form.html.erb** - Great tips about studio pairing and entry workflow
8. **formations/_info_box.html.erb** - Clear explanation of complex formation rules
9. **multis/_form.html.erb** - Excellent multi-dance feature explanation
10. **scores/heatlist.html.erb** - Comprehensive judge workflow guidance
11. **scores/_by_studio.html.erb** - Clear scoring methodology explanation
12. **solos/djlist.html.erb** - Excellent troubleshooting guide
13. **studios/_form.html.erb** - Great studio pairing explanation
14. **event/settings/heats.html.erb** - Perfect slider system explanation

### Good Info-Boxes ✓
Accurate and helpful, but could be enhanced:

15. **event/publish.html.erb** - Good but missing QR code/font customization info
16. **event/settings/options.html.erb** - Good philosophical explanation
17. **event/settings/prices.html.erb** - Good overview of packages vs options
18. **event/settings/judging.html.erb** - Basic, could add scoring system comparison
19. **event/settings/description.html.erb** - Good with helpful examples
20. **event/settings/advanced.html.erb** - Good warnings about data impact
21. **event/settings/staff.html.erb** - Basic, could add role examples
22. **event/settings/clone.html.erb** - Good expectations setting
23. **event/showcases.html.erb** - Good meta-help about info-box system
24. **event/regions.html.erb** - Good global navigation info
25. **event/ages.html.erb** - Good format explanation, needs example
26. **event/levels.html.erb** - Good warnings about safe changes
27. **event/dances.html.erb** - Good warnings about safe/unsafe changes
28. **people/index.html.erb** - Basic but sufficient
29. **people/_form.html.erb** - Good warning about deletion, plus duplicate name handling
30. **people/_info_box.html.erb** (partial) - Good role-specific guidance
31. **heats/edit.html.erb** - Good tips about decimal numbers
32. **heats/limits.html.erb** - Good explanation of limit system
33. **dances/index.html.erb** - Good drag-drop explanation
34. **dances/_form.html.erb** - Good warning about deletion
35. **dances/form.html.erb** - Basic but sufficient
36. **dances/heats.html.erb** - Good color coding explanation
37. **solos/index.html.erb** - Good drag-drop workflow
38. **solos/new.html.erb** - Good distinction from formations
39. **tables/new.html.erb** - Good workflow explanation
40. **tables/edit.html.erb** - Good feature coverage
41. **tables/arrange.html.erb** - Basic but sufficient
42. **tables/studio.html.erb** - Good color coding explanation
43. **scores/_info_box.html.erb** (partial) - Good dynamic content
44. **billables/edit.html.erb** - Good package explanation
45. **feedbacks/index.html.erb** - Good editing instructions
46. **showcases/new_request.html.erb** - Good expectations setting
47. **admin/index.html.erb** - Good workflow overview (duplicate of root)

### Minimal Info-Boxes ⚠️
Too basic, need expansion:

48. **people/backs.html.erb** - Only mentions form location, needs back number explanation
49. **scores/multis.html.erb** - Too basic, needs scrutineering info
50. **scores/callbacks.html.erb** - Needs callback calculation explanation
51. **scores/by_level.html.erb** - Too basic, needs scoring system info
52. **scores/by_age.html.erb** - Too basic, needs aggregation info

---

## Missing Info-Boxes: Priority Analysis

### HIGH PRIORITY (15 pages) 🔴
**These pages need info-boxes - they are complex navigation hubs or have non-obvious workflows:**

#### Studios Section
1. **studios/index.html.erb** - Main studios list, primary navigation hub
   - *Needs:* Explanation of table counts, invoices, ballroom assignments, studio pairing
   - *Access:* Root → Studios button

2. **studios/show.html.erb** - Complex studio detail page
   - *Needs:* Guide to action buttons (Add Person, Tables, Solos, Sheets, Invoices, Scores)
   - *Access:* Studios index → Click studio name

3. **studios/solos.html.erb** - Studio-specific solos with song management
   - *Needs:* Song playback, formation editing, DJ preparation workflow
   - *Access:* Studio show → Solos button

#### Event Summary & Reporting
4. **event/summary.html.erb** - Major hub page with comprehensive statistics
   - *Needs:* Explanation of sections (packages, options, score views, heat counts)
   - *Access:* Root → Summary button

#### Entries Management
5. **entries/index.html.erb** - Complex filtering with level/age splits
   - *Needs:* Filter usage, multi-dance split management, couple type filtering
   - *Access:* Navigation from various pages

6. **people/entries.html.erb** - Bulk entry creation form
   - *Needs:* Closed/Open category workflow, bulk entry patterns
   - *Access:* Person show → Add/Edit Entries button

#### Score Views (Public-facing)
7. **scores/instructor.html.erb** - Live instructor scores
   - *Needs:* Scrutineering rules, auto-refresh, score interpretation
   - *Access:* Summary → Instructor Scores

8. **scores/pros.html.erb** - Professional scores view
   - *Needs:* Scoring system explanation, public vs private views
   - *Access:* Summary → Pro Scores

9. **scores/by_studio.html.erb** - Studio-aggregated scores (main page, not partial)
   - *Needs:* Total vs average scoring, studio comparison methodology
   - *Access:* Summary → Scores by Studio

#### People Management
10. **people/couples.html.erb** - Couples listing with filtering
    - *Needs:* Couple type explanation, level/age filtering, pro-am vs amateur
    - *Access:* Summary → Couples

#### Special Features
11. **answers/index.html.erb** - Question answers for packages/options
    - *Needs:* Question system explanation, reporting workflow, export options
    - *Access:* Summary → View Question Answers

12. **billables/people.html.erb** - Person selection for packages
    - *Needs:* Selection interface, status indicators, bulk assignment
    - *Access:* Billable → People button

### MEDIUM PRIORITY (10 pages) 🟡
**These would benefit from info-boxes but are less critical:**

13. **formations/index.html.erb** - Formations list
    - *Needs:* Brief guidance on formation vs solo distinction
    - *Access:* Navigation

14. **multis/index.html.erb** - Multi-dances list
    - *Needs:* Brief explanation of multi-dance concept, use cases
    - *Access:* Dances index → Multi-dances section

15. **songs/index.html.erb** - Songs management
    - *Needs:* Song upload workflow, audio format support
    - *Access:* Navigation

16. **event/counter.html.erb** - Heat counter display
    - *Needs:* Purpose explanation, customization (background/color)
    - *Access:* Publish → Counter link

17. **scores/comments.html.erb** - Judge comments report
    - *Needs:* Purpose, export options, filtering
    - *Access:* Navigation

18. **showcases/index.html.erb** - Multi-location showcase coordination
    - *Needs:* Showcase relationship explanation
    - *Access:* Admin navigation

19. **locations/index.html.erb** - Multi-tenant management
    - *Needs:* Location vs event distinction, sister locations
    - *Access:* Admin navigation

20. **people/staff.html.erb** - Event staff listing (if separate page exists)
    - *Needs:* Staff role filtering, assignment workflow
    - *Access:* Navigation

21. **heats/book.html.erb** - Heat book view
    - *Needs:* Print preparation, heat grouping
    - *Access:* Navigation

22. **songs/dancelist.html.erb** - Dance-specific song list
    - *Needs:* Song selection for DJ, playlist management
    - *Access:* Dances index → Click song count

### LOW PRIORITY / NOT NEEDED (170+ pages) ⚪
**These pages don't need info-boxes:**

- Simple show pages (just display + edit/delete buttons)
- Form pages that use partials already containing info-boxes
- PDF/print-only views
- Admin-only advanced features
- Simple list pages with self-explanatory content

---

## Existing Info-Box Issues

### Issues Requiring Updates

1. **people/backs.html.erb** - Too minimal
   - *Current:* "At the bottom of this page is a form..."
   - *Add:* Explanation of back number purpose, assignment strategy, printing

2. **scores/multis.html.erb** - Too minimal
   - *Current:* "Click on a heat name..."
   - *Add:* Scrutineering explanation, callback system, score interpretation

3. **scores/callbacks.html.erb** - Missing calculation info
   - *Current:* Only explains highlighting
   - *Add:* How callbacks are calculated, rules, thresholds

4. **scores/by_level.html.erb** - Too minimal
   - *Current:* "Click on Followers or Leaders..."
   - *Add:* Scoring aggregation methodology, level comparison

5. **scores/by_age.html.erb** - Too minimal
   - *Current:* "Click on Followers or Leaders..."
   - *Add:* Age category scoring, cross-age comparisons

6. **event/publish.html.erb** - Missing features
   - *Current:* Covers printing and labels
   - *Add:* QR code generation, font customization, web view options

7. **event/settings/judging.html.erb** - Missing comparison
   - *Current:* Just references docs
   - *Add:* Brief comparison of scoring systems (1/2/3/F vs GH/G/S/B vs numbers)

8. **event/ages.html.erb** - Missing example
   - *Current:* Explains format
   - *Add:* Concrete example like "A1: Ages 18-25"

### Duplicates to Consolidate

1. **admin/index.html.erb** and **event/root.html.erb** - Identical content
   - *Recommendation:* Create shared partial `event/_root_info_box.html.erb`

2. **event/showcases.html.erb** and **event/regions.html.erb** - Similar meta-help
   - *Recommendation:* Consider consolidating or referencing shared concepts

---

## Strengths of Current Implementation

✅ **Excellent Coverage** - Most major features have helpful info-boxes
✅ **Good Use of Partials** - 3 reusable partials reduce duplication
✅ **Clear Warnings** - Red text effectively highlights destructive actions
✅ **Workflow Guidance** - Many boxes explain step-by-step processes
✅ **Practical Examples** - Concrete examples (Avery labels, date formats)
✅ **Dynamic Content** - Scoring info-box uses helpers for context-specific guidance
✅ **Conditional Display** - Some boxes shown by default for critical info
✅ **Cross-linking** - Good use of links to related pages/documentation
✅ **Color Coding Explained** - Yellow backgrounds, red warnings, green highlights

---

## Recommendations

### Phase 1: Fix Existing Issues (5 pages)
*Quick wins - improve minimal info-boxes:*

1. Expand **people/backs.html.erb**
2. Expand **scores/multis.html.erb**
3. Expand **scores/callbacks.html.erb**
4. Expand **scores/by_level.html.erb**
5. Expand **scores/by_age.html.erb**

### Phase 2: Core Navigation Hubs (4 pages)
*Essential for first-time users:*

1. Add to **studios/index.html.erb**
2. Add to **studios/show.html.erb**
3. Add to **event/summary.html.erb**
4. Add to **entries/index.html.erb**

### Phase 3: Complex Workflows (4 pages)
*Non-obvious features needing guidance:*

1. Add to **people/entries.html.erb**
2. Add to **studios/solos.html.erb**
3. Add to **billables/people.html.erb**
4. Add to **answers/index.html.erb**

### Phase 4: Public Score Pages (3 pages)
*Important for studio owners and participants:*

1. Add to **scores/instructor.html.erb**
2. Add to **scores/pros.html.erb**
3. Add to **scores/by_studio.html.erb** (main page)

### Phase 5: Enhancement (6 pages)
*Improve existing info-boxes:*

1. Update **event/publish.html.erb**
2. Update **event/settings/judging.html.erb**
3. Update **event/ages.html.erb**
4. Consolidate **admin/index.html.erb** and **event/root.html.erb**
5. Add to **people/couples.html.erb**
6. Add to **event/counter.html.erb**

### Phase 6: Medium Priority (10 pages)
*Nice-to-have improvements:*

1-10. Add to medium priority pages as time permits

---

## Implementation Pattern

### Standard Info-Box Structure
```erb
<div data-controller="info-box">
  <div class="info-button">&#x24D8;</div>
  <ul class="info-box">
    <li>First important point</li>
    <li>Second important point with <%= link_to 'helpful link', some_path %></li>
    <li class="text-red-600">⚠️ Important warning about destructive actions</li>
  </ul>
</div>
```

### Conditional Info-Box (shown by default)
```erb
<div data-controller="info-box">
  <div class="info-button">&#x24D8;</div>
  <ul class="info-box" style="display: block;">
    <li>Critical information shown by default</li>
  </ul>
</div>
```

### Reusable Partial Pattern
```erb
<!-- In _info_box.html.erb partial -->
<div data-controller="info-box">
  <div class="info-button">&#x24D8;</div>
  <ul class="info-box">
    <% if @context == 'students' %>
      <li>Student-specific guidance</li>
    <% elsif @context == 'judges' %>
      <li>Judge-specific guidance</li>
    <% end %>
  </ul>
</div>

<!-- In view that uses it -->
<%= render 'shared/info_box', context: 'students' %>
```

---

## Success Metrics

**Current State:**
- Info-box coverage: 52/283 pages (18%)
- Quality issues: 5 minimal, 2 duplicates, 3 missing features

**Target State (After All Phases):**
- Info-box coverage: 82/283 pages (29%)
  - All high-priority pages: 15 new + 5 fixes
  - All medium-priority pages: 10 new
  - Quality improvements: 3 enhancements + 2 consolidations
- Zero minimal/incomplete info-boxes
- All navigation hubs have guidance
- All complex workflows documented

---

## Conclusion

The showcase application has a **solid foundation** of info-box implementations. The existing 52 info-boxes are generally well-written and helpful. The main gaps are:

1. **Navigation hubs** (studios, summary, entries) lack guidance
2. **Scoring pages** need expansion and public-facing explanation
3. **Complex workflows** (entries, table assignments, formations) need more context
4. **5 existing info-boxes** are too minimal and need expansion

The recommended phased approach prioritizes:
- **Phase 1-2:** Fix existing issues + add to core hubs (9 pages)
- **Phase 3-4:** Complex workflows + public pages (7 pages)
- **Phase 5-6:** Enhancements + nice-to-haves (16 pages)

**Total effort:** 32 pages to achieve comprehensive coverage of all user-facing features.

---

## Appendix: Complete File List

### Files WITH Info-Boxes (52)
See "Current State: Pages WITH Info-Boxes" section above for full analysis.

### Files NEEDING Info-Boxes by Section

**Studios (3):**
- studios/index.html.erb
- studios/show.html.erb
- studios/solos.html.erb

**Event/Settings (2):**
- event/summary.html.erb
- event/counter.html.erb

**People (3):**
- people/entries.html.erb
- people/couples.html.erb
- people/staff.html.erb (if exists as separate page)

**Entries (1):**
- entries/index.html.erb

**Scores (5):**
- scores/instructor.html.erb
- scores/pros.html.erb
- scores/by_studio.html.erb (main page)
- scores/comments.html.erb
- (Plus 5 existing that need expansion)

**Other (6):**
- answers/index.html.erb
- billables/people.html.erb
- formations/index.html.erb
- multis/index.html.erb
- songs/index.html.erb
- songs/dancelist.html.erb

**Admin (2):**
- showcases/index.html.erb
- locations/index.html.erb

**Heats (1):**
- heats/book.html.erb

---

*End of Report*
