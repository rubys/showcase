# JavaScript Heat List Implementation Plan

## Overview

Implement JavaScript rendering for the heat list view (`/scores/:judge/heats`) by converting `heatlist.html.erb` to JavaScript using the existing ERB-to-JS converter. This achieves parity with the ERB template while enabling offline-capable heat list navigation.

**Status**: Planning
**Target**: Complete behavioral parity with ERB heat list
**Verification**: `scripts/render_erb_and_js.rb` comparing ERB vs. JS output

---

## Current State

**What exists:**
- ✅ ERB heat list template (`heatlist.html.erb`) - 107 lines
- ✅ Route `/scores/:judge/heats` → `scores#spa` action
- ✅ Bulk data endpoint `/scores/:judge/heats/data` (normalized JSON)
- ✅ ERB-to-JS converter (`lib/erb_to_js_converter.rb`)
- ✅ `heat_app_controller.js` with `showHeatList()` stub
- ✅ Debug script extended to handle heat lists
- ✅ Forms already use Stimulus `auto-submit` controller

**What's missing:**
- ❌ JavaScript heat list template (converted from ERB)
- ❌ Heat list data in bulk JSON (agenda, unassigned, scored, missed)
- ❌ Heat list rendering logic in `heat_app_controller.js`

**Current output:**
- **ERB**: 86,180 bytes, 147 `<tr>` tags
- **JS**: 65 bytes (placeholder: "Coming soon...")

---

## Simplified Approach

**Key insight**: The forms don't need to work offline - they already use Stimulus `auto-submit` controller and work via Turbo. We just need to:

1. Extend `/scores/:judge/heats/data` to include computed fields (agenda, unassigned, scored, missed)
2. Convert `heatlist.html.erb` to JavaScript using existing converter
3. Wire up `showHeatList()` to call the converted template function
4. Forms remain functional via existing Stimulus controller

**No partials needed.** **No complex client-side computation.** Just convert and render.

---

## Phase 1: Extend Bulk Data Endpoint

### 1.1 Add Computed Fields to `/scores/:judge/heats/data`

**File**: `app/controllers/scores_controller.rb` (method `heats_data`, lines 115+)

Currently returns:
```ruby
{
  event: event,
  judge: judge,
  heats: [...],
  people: {...},
  entries: {...},
  # ... other lookups
}
```

Need to add:
```ruby
{
  # ... existing fields ...

  # Heat list specific data
  agenda: agenda_hash,           # { heat_number => "Category Name" }
  unassigned: unassigned_array,  # [heat_number, ...]
  scored: scored_hash,            # { heat_number => true/false }
  missed: missed_array,           # [heat_number, ...]
  style: params[:style] || 'radio',
  sort: judge.sort_order || 'back',
  show: judge.show_assignments || 'first',
  show_solos: determine_show_solos(event),
  combine_open_and_closed: event.combine_open_and_closed?,
  assign_judges: event.assign_judges > 0
}
```

**Extract logic from `heatlist` action** (lines 227-268):

```ruby
def heats_data
  event = Event.current
  judge = Person.find(params[:judge].to_i)

  # ... existing heat/people/entry loading ...

  # Compute agenda (from heatlist action)
  agenda = {}
  # ... agenda computation logic ...

  # Compute unassigned (from heatlist action)
  unassigned = []
  # ... unassigned logic ...

  # Compute scored (from heatlist action)
  scored = {}
  # ... scored logic ...

  # Compute missed (from heatlist action)
  missed = []
  # ... missed logic ...

  render json: {
    event: event.as_json(...),
    judge: judge.as_json(...),
    heats: heats_json,
    # ... existing lookups ...

    # Heat list data
    agenda: agenda,
    unassigned: unassigned,
    scored: scored,
    missed: missed,
    style: params[:style] || 'radio',
    sort: judge.sort_order || 'back',
    show: judge.show_assignments || 'first',
    show_solos: @show_solos,
    combine_open_and_closed: event.combine_open_and_closed?,
    assign_judges: event.assign_judges > 0,
    qr_code: RQRCode::QRCode.new(judge_heatlist_url(judge, style: params[:style] || 'radio')).as_svg(viewbox: true)
  }
end
```

**Note**: This means the bulk data endpoint now includes heat list fields even for individual heat requests. That's fine - it's only computed once per page load and adds minimal overhead.

---

## Phase 2: Convert ERB Template to JavaScript

### 2.1 Add Heat List Template to Templates Controller

**File**: `app/controllers/templates_controller.rb`

```ruby
def scoring
  # Convert _heat.html.erb (existing)
  heat_template = File.read(Rails.root.join('app/views/scores/_heat.html.erb'))
  heat_js = ErbToJsConverter.new.convert(heat_template)

  # Convert heatlist.html.erb (NEW)
  heatlist_template = File.read(Rails.root.join('app/views/scores/heatlist.html.erb'))
  heatlist_js = ErbToJsConverter.new.convert(heatlist_template, function_name: 'heatlist')

  # Export both functions
  render js: "#{heat_js}\n\n#{heatlist_js}", content_type: 'text/javascript'
end
```

**Converter options** (if needed):
```ruby
ErbToJsConverter.new.convert(
  heatlist_template,
  function_name: 'heatlist',
  data_var: 'data'  # Use 'data' instead of default '@' prefix
)
```

### 2.2 Handle Rails Helpers

The converter should already handle most helpers, but verify these work:

**`link_to`** - Converts to anchor tag with href
```ruby
<%= link_to heat.number, link %>
# Becomes:
html += `<a href="${link}">${heat.number}</a>`;
```

**`dom_id`** - Already implemented
```ruby
<%= dom_id heat %>
# Becomes:
domId(heat)
```

**`judge_heatlist_url`** - Convert to string template
```ruby
judge_heatlist_url(@judge, style: @style)
# Becomes:
`/scores/${data.judge.id}/heatlist?style=${data.style}`
```

**Path helpers** - Convert to string templates
```ruby
judge_heat_path(judge: @judge, heat: heat.number, style: @style)
# Becomes:
`/scores/${data.judge.id}/heat/${heat.number}?style=${data.style}`
```

**QR Code SVG** - Already in data as HTML string
```ruby
<%= RQRCode::QRCode.new(...).as_svg(viewbox: true).html_safe %>
# Becomes:
html += data.qr_code;
```

### 2.3 Test Conversion

Run the conversion and check for errors:

```bash
RAILS_APP_DB=2025-barcelona-november ruby scripts/render_erb_and_js.rb 83
```

**Expected first result**: Likely some mismatches or errors

**Debug process**:
1. Check `/tmp/scoring_templates.js` for the generated `heatlist()` function
2. Compare `/tmp/erb_rendered.html` vs `/tmp/js_rendered.html`
3. Fix converter issues or add helper mappings
4. Iterate until output matches

---

## Phase 3: Wire Up Stimulus Controller

### 3.1 Implement showHeatList()

**File**: `app/javascript/controllers/heat_app_controller.js` (lines 146-150)

Replace stub:
```javascript
showHeatList() {
  console.debug('Rendering heat list...')
  this.element.innerHTML = '<h1>Heat List</h1><p>Coming soon...</p>'
}
```

With actual implementation:
```javascript
showHeatList() {
  console.debug('Rendering heat list...')

  try {
    // Use raw data directly - no hydration needed
    const data = this.rawData

    console.debug(`Rendering ${data.heats.length} heats`)

    // Render using converted template
    const html = this.templates.heatlist(data)

    // Replace content
    this.element.innerHTML = html

    // Attach event listeners for heat links
    this.attachHeatListListeners()

    console.debug('Heat list rendered successfully')

  } catch (error) {
    console.error('Failed to render heat list:', error)
    this.showError(`Failed to render heat list: ${error.message}`)
  }
}

attachHeatListListeners() {
  // Intercept clicks on heat links to navigate within SPA
  this.element.querySelectorAll('a[href*="/heat/"]').forEach(link => {
    link.addEventListener('click', (e) => {
      e.preventDefault()
      const url = new URL(link.href, window.location.origin)
      const heatMatch = url.pathname.match(/\/heat\/(\d+\.?\d*)/)
      if (heatMatch) {
        const heatNumber = parseFloat(heatMatch[1])
        this.navigateToHeat(heatNumber)
      }
    })
  })

  // Forms already work via Stimulus auto-submit controller
  // No additional wiring needed!
}
```

### 3.2 Update URL State

When showing heat list, clear heat parameter:

```javascript
showHeatList() {
  // Update URL to show we're on heat list
  const url = new URL(window.location)
  url.searchParams.delete('heat')
  window.history.pushState({}, '', url)

  // Render list
  console.debug('Rendering heat list...')
  // ... rest of implementation
}
```

---

## Phase 4: Testing and Verification

### 4.1 Run Comparison Script

```bash
RAILS_APP_DB=2025-barcelona-november ruby scripts/render_erb_and_js.rb 83
```

**Success criteria**:
```
✓ Row counts match!
ERB: 147 rows, 86180 bytes
JS:  147 rows, ~86000 bytes
```

**If mismatches occur**:
1. Compare files: `diff /tmp/erb_rendered.html /tmp/js_rendered.html`
2. Identify differences (often whitespace, attribute order, or helper conversion issues)
3. Fix converter or add helper mappings
4. Re-run until outputs match

### 4.2 Manual Browser Testing

**Test in browser** at `http://localhost:3000/scores/83/heats`:

1. ✅ Heat list renders with all heats
2. ✅ Agenda category headers display
3. ✅ Color coding correct (red/slate-400/black)
4. ✅ QR code displays
5. ✅ Unassigned warning appears (if applicable)
6. ✅ Clicking heat navigates to individual heat
7. ✅ Browser back button returns to heat list
8. ✅ Sort order form works (via Stimulus)
9. ✅ Show assignments form works (via Stimulus)

### 4.3 Test Offline Behavior

1. Load heat list
2. Open DevTools → Network → Throttling → Offline
3. Click different heats → Should still navigate (data already loaded)
4. Forms won't work offline (that's expected and fine)

---

## Phase 5: Edge Cases

### 5.1 Fractional Heat Numbers

Heat numbers can be fractional (e.g., 123.5):
- Verify `parseFloat()` used in navigation
- Test clicking fractional heat links

### 5.2 Multi-Dance Heats

Multi-dance heats link to slot 1:
```ruby
heat.category == 'Multi' ?
  judge_heat_slot_path(judge: @judge, heat: heat.number, slot: 1, style: @style)
  : judge_heat_path(judge: @judge, heat: heat.number, style: @style)
```

Verify slot links work (though slot navigation not yet implemented in SPA).

### 5.3 Recordings Mode

When `style === 'recordings'`:
- Different path structure
- No scoring UI
- Verify templates handle correctly

### 5.4 Empty States

Test with events that have:
- No heats (should show empty table)
- All heats scored (all slate-400)
- No unassigned heats (no warning)

---

## Success Criteria

### Functional Requirements
- [ ] Heat list renders all heats (147 rows for Barcelona event)
- [ ] Agenda category headers display correctly
- [ ] Color coding matches ERB (red/slate-400/black)
- [ ] Heat links navigate within SPA (no page reload)
- [ ] Sort and filter forms work (via existing Stimulus)
- [ ] QR code displays
- [ ] Unassigned warning appears when relevant
- [ ] Browser back button works

### Technical Requirements
- [ ] `render_erb_and_js.rb` shows matching row counts
- [ ] No console errors in browser
- [ ] Works offline (navigation only - forms fail gracefully)
- [ ] Progressive enhancement (forms work without JS via Turbo)

### Testing Requirements
- [ ] Comparison script passes (matching output)
- [ ] Manual browser testing complete
- [ ] Edge cases verified (fractional, multi, recordings)

---

## Implementation Steps (Recommended Order)

1. **Phase 1**: Extend bulk data endpoint (add computed fields to JSON)
2. **Phase 2**: Convert ERB template and iterate until comparison passes
3. **Phase 3**: Wire up Stimulus controller (10-20 lines of code)
4. **Phase 4**: Test and verify
5. **Phase 5**: Handle edge cases

**Estimated effort**: 3-4 hours
- Phase 1: 1 hour (extract computation logic to JSON)
- Phase 2: 1-2 hours (conversion and debugging)
- Phase 3: 30 minutes (Stimulus wiring)
- Phase 4-5: 1 hour (testing)

---

## Why This Is Simple

1. **No partial extraction** - Convert entire template directly
2. **No client-side computation** - Server provides all computed fields
3. **No form handling** - Forms already work via Stimulus/Turbo
4. **No new patterns** - Same approach as individual heat conversion
5. **Proven tooling** - ERB-to-JS converter already works
6. **Verification built-in** - `render_erb_and_js.rb` confirms parity

**The hard work is already done.** We just need to:
- Add fields to JSON
- Run the converter
- Wire up the template call

---

## Open Questions (Resolved)

~~1. Should we extract a partial?~~
- **No** - Convert entire template directly

~~2. Should forms work offline?~~
- **No** - Forms use Turbo/Stimulus, work online only (acceptable)

~~3. Should we compute agenda/scored client-side?~~
- **No** - Add to server JSON (simpler, matches ERB logic exactly)

~~4. How do users navigate back to list?~~
- **Browser back button** - URL state managed via `history.pushState()`

~~5. Should we handle POST requests in JS?~~
- **No** - Existing Stimulus controller handles form submission

---

## Dependencies

- ✅ ERB-to-JS converter working
- ✅ Heat rendering working (proven approach)
- ✅ Bulk data endpoint exists
- ✅ Stimulus controller scaffolding exists
- ✅ Debug script handles heat lists
- ✅ Forms already wired to Stimulus
- ⚠️ Need to extend JSON with computed fields

---

## Risk Assessment

**Low Risk:**
- Template conversion (proven approach, same as heat conversion)
- Stimulus wiring (straightforward, ~20 lines)
- Navigation (URL management, already working for heats)

**No Medium or High Risk Items**

**Mitigation:**
- Use comparison script for continuous verification
- Incremental implementation
- Browser testing at each step
