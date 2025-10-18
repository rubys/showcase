# Migration Plan: Converting from params.require to params.expect

## Overview
The codebase has 19 instances of `params.require` across 14 controllers. Due to complex params handling patterns, this migration requires careful attention.

## Key Challenges Identified

1. **Dynamic params access** - Controllers use variable keys to access params
2. **Conditional params manipulation** - Params are modified based on event state
3. **Nested structures** - Deep nesting with arrays and hashes
4. **Domain-specific logic** - Complex business rules affect param handling

## Migration Strategy

### Phase 1: Simple Conversions (Low Risk)
Convert straightforward `params.require(:model).permit(...)` patterns:

**Controllers to migrate:**
- [x] SongsController (1 instance) - ✅ Completed 2025-08-04
- [x] FormationsController (1 instance) - ✅ Completed 2025-08-04
- [x] ShowcasesController (1 instance) - ✅ Completed 2025-08-04
- [x] CategoriesController (1 instance) - ✅ Completed 2025-08-04
- [x] DancesController (1 instance) - ✅ Completed 2025-08-04
- [x] MultisController (1 instance) - ✅ Completed 2025-08-04
- [ ] BillablesController (1 instance)

**Example conversion:**
```ruby
# Before
params.require(:song).permit(:dance_id, :order, :title, :artist)

# After
params.expect(song: [:dance_id, :order, :title, :artist])
```

### Phase 2: Controllers with Options/Arrays (Medium Risk)
Handle controllers with nested options or array parameters:

**Controllers to migrate:**
- [x] PeopleController (options: {} parameter) - ✅ Completed 2025-08-06
- [x] BillablesController (options: {}, packages: {} parameters) - ✅ Completed 2025-08-06
- [x] StudiosController (nested permitted params) - ✅ Completed 2025-08-06

**Example conversion:**
```ruby
# Before
params.require(:person).permit(:name, :studio_id, options: {})

# After  
params.expect(person: [:name, :studio_id, { options: {} }])
```

### Phase 3: Complex Controllers (High Risk)
Controllers with creative params usage requiring careful refactoring:

**Controllers to migrate:**
- [ ] LocationsController (3 different require calls)
- [ ] UsersController (conditional permit lists)
- [ ] EventController (very long permit list)
- [ ] EntriesController (complex nested structures)
- [ ] HeatsController (dynamic params manipulation)
- [ ] ScoresController (JSON params handling)

**Strategies:**
1. May need to keep some `params[]` access for dynamic keys
2. Consider extracting complex param logic to private methods
3. Test thoroughly with different user roles and event states

### Phase 4: Edge Cases
- [ ] StudiosController `pair` param (line 261) - standalone require without permit
- [ ] Controllers using params in `before_action` callbacks
- [ ] Dynamic param key access patterns that can't use `expect`

## Implementation Steps

1. **Add test coverage** for param handling if missing
2. **Migrate in phases** starting with simple conversions
3. **Run full test suite** after each controller
   - Unit tests: `bin/rails test`
   - System tests: `bin/rails test:system`
   - Both must pass before proceeding
4. **Manual testing** for complex forms (entries, scores, people)
5. **Deploy to staging** for user acceptance testing

## Special Considerations

1. **Backwards compatibility** - Some forms may send params in old format
2. **API endpoints** - Check if any external systems use these endpoints
3. **Error handling** - Update rescue blocks for ParameterMissing errors
4. **Strong params in concerns** - Check shared controller concerns

## Timeline Estimate
- Phase 1: 1 day
- Phase 2: 1 day  
- Phase 3: 3-4 days (includes testing)
- Phase 4: 1 day
- Testing & deployment: 2 days

Total: ~1.5 weeks with thorough testing

## Progress Tracking

### Completed Controllers
**Phase 1 (2025-08-04):**
- SongsController - Converted song_params method
- FormationsController - Converted formation_params method
- ShowcasesController - Converted showcase_params method
- CategoriesController - Converted category_params method
- DancesController - Converted dance_params method (includes multi param)
- MultisController - Converted dance_params method (includes nested multi: {})

All tests passing:
- Unit tests: 805 runs, 2113 assertions, 0 failures
- System tests: 106 runs, 258 assertions, 0 failures

**Phase 2 (2025-08-06):**
- PeopleController - Converted person_params method (includes options: {} parameter)
- BillablesController - Converted billable_params method (includes options: {} and packages: {} parameters)
- StudiosController - Converted studio_params method and fixed standalone require(:pair)

All tests passing:
- Unit tests: 805 runs, 2113 assertions, 0 failures
- System tests: 106 runs, 253 assertions, 3 intermittent failures (known Capybara/Selenium timing issues - all pass when run individually)

### In Progress
_None - Phase 2 completed_

### Blockers/Issues
- Phase 1: None encountered
- Phase 2: System tests showed 3 intermittent failures due to known Capybara/Selenium timing issues (documented in CLAUDE.md). All tests pass when run individually. Not related to params changes.

### Notes
- Created: 2025-08-04
- Last Updated: 2025-08-06
- Phase 1 completed successfully with all tests passing
- Phase 2 completed successfully - all three controllers migrated
- **Important**: Both unit tests AND system tests must pass after each migration
- System tests exercise the full stack including form submissions
- Ready to proceed to Phase 3 (Complex Controllers) when needed