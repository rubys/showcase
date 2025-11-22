# Next Steps: ERB-to-Stimulus Template Architecture

## Architecture Decision: New Routes & Actions ✅

Instead of adding JSON format to existing actions, we're creating **new dedicated JSON endpoints**:

- `/scores/:judge/heats` → Heat list (already exists as `heats_json`)
- `/scores/:judge/heats/:heat` → Individual heat data (new `heats_show` action)

This keeps the old ERB views (`/scores/:judge/heatlist`, `/scores/:judge/heat/:heat`) completely untouched and available as fallback.

## What's Been Completed ✅

1. **ERB-to-JS Converter** (42 tests passing)
   - `lib/erb_to_js_converter.rb`
   - `test/lib/erb_to_js_converter_test.rb`
   - `app/controllers/templates_controller.rb` → `/templates/scoring.js`

2. **Stimulus Shell View**
   - `app/views/scores/spa.html.erb` → Uses `data-controller="heat-app"`

3. **Initial Stimulus Controller**
   - `app/javascript/controllers/heat_app_controller.js` (skeleton created)

## Next Steps

### Step 1: Add heats_show Action to scores_controller.rb

Add this new action (see `/tmp/heats_show_action.rb` for full code):

```ruby
# GET /scores/:judge/heats/:heat - JSON endpoint for individual heat
def heats_show
  # Sets all instance variables needed by templates:
  # @event, @judge, @number, @slot, @style, @subjects, @heat,
  # @scores, @ballrooms, @results, @combine_open_and_closed, etc.

  render json: {
    event: @event,
    judge: @judge,
    subjects: @subjects,
    # ... all template data
  }
end
```

**Location**: Add after line 815 in `app/controllers/scores_controller.rb`

### Step 2: Add Route

In `config/routes.rb`, add after line 216:

```ruby
get '/scores/:judge/heats/:heat', to: 'scores#heats_show',
    defaults: { format: :json }, as: 'judge_heats_show', heat: /\d+\.?\d*/
```

### Step 3: Complete heat_app_controller.js

Update `app/javascript/controllers/heat_app_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { judge: Number, heat: Number, style: String, basePath: String }

  async connect() {
    // Load converted templates
    this.templates = await this.loadTemplates()

    if (this.hasHeatValue) {
      await this.showHeat(this.heatValue)
    } else {
      await this.showHeatList()
    }
  }

  async loadTemplates() {
    const response = await fetch('/templates/scoring.js')
    const code = await response.text()

    // Execute module code and extract exports
    const module = { exports: {} }
    const func = new Function('module', 'exports', code + '; return { soloHeat, rankHeat, tableHeat, cardsHeat };')
    return func(module, module.exports)
  }

  async showHeat(heatNumber) {
    const response = await fetch(
      `${this.basePathValue}/scores/${this.judgeValue}/heats/${heatNumber}?style=${this.styleValue}`
    )
    const data = await response.json()

    // Select template
    let html
    if (data.heat.category === 'Solo') {
      html = this.templates.soloHeat(data)
    } else if (data.final) {
      html = this.templates.rankHeat(data)
    } else if (data.style !== 'cards' || data.scores.length === 0) {
      html = this.templates.tableHeat(data)
    } else {
      html = this.templates.cardsHeat(data)
    }

    this.element.innerHTML = html
    // Stimulus controllers (score, open-feedback, drop) auto-attach!
  }

  async showHeatList() {
    const response = await fetch(
      `${this.basePathValue}/scores/${this.judgeValue}/heats`
    )
    const data = await response.json()

    // TODO: Render heat list
    this.element.innerHTML = '<h1>Heat List</h1>'
  }
}
```

### Step 4: Test the New Endpoint

```bash
# Start server
bin/dev

# Test JSON endpoint directly
curl http://localhost:3000/scores/1/heats/1.0

# Open SPA in browser
open http://localhost:3000/scores/1/spa?heat=1
```

### Step 5: Verify Stimulus Controllers Attach

1. Open browser dev tools
2. Navigate to `/scores/1/spa?heat=1`
3. Verify HTML renders
4. Check that data-controller attributes are present
5. Test that score submission works (existing score controller)
6. Test that feedback panel opens (existing open-feedback controller)

## Key Benefits of This Approach

✅ **Clean separation**: Old ERB views untouched
✅ **Simple routes**: `/heats/` for new, `/heat/` for old
✅ **No respond_to blocks**: Dedicated JSON actions
✅ **Easy rollback**: Just change spa.html.erb back
✅ **Battle-tested**: Same code online and offline

## Files to Change

1. `app/controllers/scores_controller.rb` - Add `heats_show` action
2. `config/routes.rb` - Add route for `/scores/:judge/heats/:heat`
3. `app/javascript/controllers/heat_app_controller.js` - Complete rendering logic

## Files Already Complete

✅ `lib/erb_to_js_converter.rb`
✅ `test/lib/erb_to_js_converter_test.rb` (42 tests)
✅ `app/controllers/templates_controller.rb`
✅ `app/views/scores/spa.html.erb`

## Testing Checklist

- [ ] JSON endpoint returns correct data structure
- [ ] All 4 heat types render correctly (Solo, Rank, Table, Cards)
- [ ] HTML structure matches ERB output
- [ ] Stimulus controllers attach and work (score, open-feedback, drop)
- [ ] Navigation works (prev/next heat)
- [ ] Offline mode works (separate task)
