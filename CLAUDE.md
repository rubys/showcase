# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Documentation

For understanding the overall system architecture, deployment model, and operational patterns, see [ARCHITECTURE.md](ARCHITECTURE.md). Review this document when:

- Working on deployment, multi-tenancy, or Navigator-related features
- Understanding how the application runs in production (Fly.io, Tigris storage, global distribution)
- Investigating performance, scaling, or infrastructure concerns
- Making changes to configuration management, CGI scripts, or lifecycle hooks
- Understanding the four-component system: Rails app, administration, Navigator reverse proxy, and glue scripts

## Rails Configuration

The application runs on Rails 8.0.2 with full Rails 8.0 configuration defaults (`config.load_defaults 8.0`).

### Rails 8.0 Migration Completed

All SQL reserved word compatibility issues have been resolved:

1. **Ordered Scopes**: Models with `order` columns use an `ordered` scope with `arel_table[:order]`:
   - `Dance.ordered`, `Category.ordered`, `Billable.ordered`, `Song.ordered`, etc.

2. **By Name Scopes**: Models with `name` columns use a `by_name` scope with `arel_table[:name]`:
   - `Person.by_name`, `Studio.by_name`, `Dance.by_name`

3. **All migrations complete**: The codebase is now fully compatible with Rails 8.0's SQL reserved word quoting requirements.

Future work could consider renaming these columns to non-reserved words for cleaner code.

## Project Overview

This is a Rails 8 application for managing ballroom dance showcase events. It handles event scheduling, heat management, scoring, and participant tracking across multiple locations and competitions.

Models are split into two categories: **Base models** support ballroom dance event management (ages, billables, categories, dances, entries, events, formations, heats, judges, people, scores, solos, studios, tables, etc.), while **Admin models** support system administration and multi-tenancy (locales, locations, regions, showcases, users).

### Frontend Architecture

This application uses **import maps** for JavaScript module management (not Webpack or esbuild). When adding JavaScript functionality:

- **Prefer Stimulus controllers** over inline scripts in views
- Stimulus controllers are located in `app/javascript/controllers/`
- Import maps configuration is in `config/importmap.rb`
- Avoid `<script>` tags with inline JavaScript in ERB templates unless absolutely necessary

The frontend primarily uses **ERB templates** with Turbo Drive for enhanced navigation and **Stimulus controllers** for interactive behaviors. This approach handles all event preparation, administration, participant management, and post-event publishing.

#### Single-Page Application (SPA) for Live Event Features
For features used heavily **during live events** (where offline capability and real-time updates are critical), the application uses a **Web Components-based SPA** approach:

**Current SPA Implementation: Judge Scoring Interface**
The judge scoring interface has been reimplemented using Web Components to provide offline-first functionality and real-time updates during events:

**Core Components:**
- `heat-page.js` - Main container managing heat navigation and state
- `heat-solo.js` - Solo heat rendering with formations and scoring
- `heat-rank.js` - Finals with drag-and-drop ranking
- `heat-table.js` - Standard heat table with radio/checkbox scoring
- `heat-cards.js` - Card-based drag-and-drop scoring interface
- `heat-header.js` - Heat details (number, dance, slot display)
- `heat-info-box.js` - Contextual help and instructions

**Data Management:**
- `HeatDataManager` - IndexedDB-based offline storage with automatic sync
- Queues scores in IndexedDB when offline, uploads when connectivity returns
- Fetches heat data from JSON endpoints (`/scores/:judge_id/heats.json`)
- ActionCable integration for live score updates during events

**Key Features:**
- **Offline-first**: Judges can score heats without network connectivity
- **Progressive enhancement**: Falls back to traditional views when JavaScript unavailable
- **Behavioral parity**: SPA matches Rails view behavior exactly (verified by comprehensive tests)
- **Real-time sync**: Live updates via ActionCable when other judges score
- **Touch-friendly**: Optimized for tablet use (iPads) during live events

**Implementation Status:**
The ERB-based judge scoring views remain in place and will only be removed once the Web Components version is proven by actual usage during live events. Both implementations coexist, with the traditional views serving as a fallback.

**When to use SPA vs Traditional:**
- **Use SPA for live event features** that require offline capability, real-time updates, or heavy interaction during events (e.g., judge scoring, heat management)
- **Use traditional ERB/Stimulus for everything else**: event preparation, administration, participant management, reporting, publishing
- The majority of the application uses and will continue to use ERB templates with Stimulus controllers

## Common Development Commands

### Running the Application

```bash
# Standard development server with foreman
bin/dev

# Run with a specific database (event)
bin/dev db/2025-boston.sqlite3

# Run with test database
bin/dev test

# Run with demo database
bin/dev demo
```

### Testing

The application has two parallel testing strategies:

#### Rails Tests (Backend, API, System)

```bash
# Run all tests except system tests
bin/rails test

# Run system tests
bin/rails test:system

# Reset database and run tests
bin/rails test:db
```

Rails tests cover:
- **Model tests**: Business logic, validations, associations
- **Controller tests**: HTTP endpoints, JSON APIs, authentication
- **Integration tests**: Multi-step workflows, complex interactions
- **System tests**: Browser-based end-to-end tests using Capybara/Selenium

#### JavaScript Tests (Frontend SPA)

```bash
# Run all JavaScript tests
npm test

# Run specific test file
npm test -- navigation.test.js

# Run tests in watch mode
npm test -- --watch
```

JavaScript tests use **Vitest** (a fast, modern test runner) and follow a **component testing philosophy**:

**Testing Philosophy:**
- **Component tests are primary**: Test component behavior in isolation with helper functions
- **System tests are minimal**: Only verify components render (3 basic tests)
- **Behavioral parity**: JavaScript tests mirror Rails behavior tests to ensure SPA matches traditional views exactly

**Test Categories:**
- `navigation.test.js` (17 tests) - Heat navigation including fractional heats and slot progression
- `semi_finals.test.js` (22 tests) - Semi-finals logic (≤8 couples skip to finals, >8 require semi-finals)
- `start_button.test.js` (20 tests) - Emcee mode start button with offline protection
- `component_selection.test.js` (20 tests) - Correct component selection based on category/properties
- `heat_details.test.js` (29 tests) - Heat header and info box display logic
- `score_posting.test.js` (13 tests) - Score submission with offline queueing
- `heat_data_manager.test.js` (12 tests) - IndexedDB storage and sync logic

**Why Component Tests:**
- **Faster**: No browser overhead, pure JavaScript execution
- **More reliable**: Less flaky than system tests, easier to debug
- **Better coverage**: Test edge cases and error conditions easily
- **Behavioral focus**: Tests verify what users see, not implementation details

**Adding New Tests:**
When adding features to the SPA, always add corresponding JavaScript tests. Follow the existing test patterns:
1. Create helper functions that mirror the component's logic
2. Test the behavior, not implementation details
3. Cover edge cases and error conditions
4. Ensure tests match Rails behavior when applicable

### Database Management

```bash
# Prepare database (creates and runs migrations)
bin/rails db:prepare

# Run migrations
bin/rails db:migrate

# Load seed data
bin/rails db:seed

# Load fixtures (for test data)
bin/rails db:fixtures:load
```

## Key Components

### Models Structure

#### Core Competition Models
- `Event` - Singleton configuration for each showcase, has attached counter_art file
- `Person` - All participants (students, professionals, guests, judges, placeholders). STI disabled. Complex package defaults and active status management. **Special case**: Person with `id = 0` (named "Nobody") is a placeholder used for studio formations and should be excluded from participant calculations like gap optimization
- `Studio` - Dance studios participating, has bidirectional pair relationships
- `Dance` - Individual dance styles (Waltz, Tango, etc.). Implements scrutineering algorithms (Rules 5-8). **Important**: When a dance appears in multiple categories, there will be multiple Dance records with the same name - only one has positive order (the canonical dance), others have `order < 0` (called "split dances"). Split dances sync certain properties (like semi_finals) from the canonical dance. Name uniqueness is only enforced for positive order dances
- `Category` - Competition categories combining age/level groupings, can be spacers (no dances). Has `use_category_scoring` (defaults to true) which works with the event's `student_judge_assignments` to enable category-based scoring - a category only uses category scoring when BOTH flags are set. The default of true provides an opt-out mechanism for specific categories
- `Age` & `Level` - Organizational structures for competition grouping (age categories and proficiency levels)
- `CatExtension` - Category splits into multiple parts when needed

#### Heat & Performance Models
- `Heat` - Scheduled dance sessions linking entries and dances. **Heats are numbered** - to determine who is on the floor for a given heat number, find all Heat records with that number, follow the entry relationship to extract lead and follow. Heats with `number >= 1` are scheduled heats. **Scratched heats** (withdrawn/canceled) have `number < 0` and are excluded from scheduling and scrutineering but can be restored or permanently deleted with the Clean action. Implements ranking algorithms (Rules 1, 5-8 for single dances, 9-11 for multi-dance compilations)
- `Entry` - Core relationship model connecting lead, follow, and instructor (all Person records) with optional studio. Has many heats. Complex logic for subject determination and invoice studios
- `Solo` - Individual performances/routines. Belongs to heat, has attached song_file. **Solos can have formations** which identify additional people on the floor beyond the lead/follow
- `Formation` - Individual participants in group performances. Belongs to person and solo. Has `on_floor` attribute indicating if they're dancing or just receiving credit. Note: while the formation controller represents a solo with multiple participants, the Formation model represents a single participant
- `Multi` - Multi-dance competitions linking parent dance to child dances
- `MultiLevel` - Defines splits for multi-dance events. Each MultiLevel belongs to a Dance and specifies a `name` (e.g., "Newcomer", "Full Bronze 65+"), optional level range (`start_level`/`stop_level`), optional age range (`start_age`/`stop_age`), and optional `couple_type`. When a multi-dance has MultiLevel records, the scheduler packs compatible splits into the same heat while keeping each split's entries together as an atomic unit for judging. The `name` is displayed in scoring views to identify which competition a judge is ranking

#### Judging & Scoring Models
- `Judge` - Judge information for a person, has many recordings
- `Score` - Judge scoring data for heats, broadcasts live updates via ActionCable. **Important**: Scores with no data (nil `good`, `bad`, `value`, and blank `comments`) are normally deleted to keep the database clean. However, when `Event.assign_judges > 0`, empty scores are kept because they indicate judge assignment - the existence of a Score record shows which judge has been assigned to that heat/couple combination. **Category scoring**: When `heat_id` is negative, it represents a category score where `heat_id = -category_id`. These scores also have `person_id` set to identify which student the category score belongs to
- `Recording` - Audio recordings by judges for heats, uploads to cloud storage

#### Financial Models
- `Billable` - Packages and options for purchase. STI disabled, type can be 'Package' or 'Option'
- `PackageInclude` - Join table linking packages to included options
- `PersonOption` - Join table for people selecting optional add-ons, relates to tables
- `Payment` - Payment records for people

#### Seating Models
- `Table` - Seating table management with grid positioning (row, col). Belongs to optional Billable (for option-specific tables)
- `StudioPair` - Paired studio relationships for table proximity

#### Music Models
- `Song` - Songs associated with dances, has attached song_file

#### Questionnaire Models
- `Question` - Questions for billable items (radio or textarea types), ordered list
- `Answer` - Person's answers to questions

#### Multi-location Models (Navigator)
- `Location` - Physical locations hosting showcases, validates locale format
- `Showcase` - Individual showcase events at locations, provides date ranges and URL generation
- `User` - Authentication and authorization with complex logic for site/event access and trust levels

#### Infrastructure Models
- `ApplicationRecord` - Base class for all models. Manages readonly mode, provides ChronicValidator for date/time parsing, handles blob uploads to Tigris storage on Fly.io
- `Region` - Deployment region configuration (STI disabled, type: 'fly' or 'kamal')
- `Locale` - Service class (not ActiveRecord) for centralized locale management and formatting

### Heat Scheduling Algorithm (app/controllers/concerns/heat_scheduler.rb)
- Two-pass scheduling: minimize heat count, then balance heat sizes
- Interleaves different dance types within agenda categories
- Manual drag-and-drop ordering for solos

### Table Assignment Algorithm (app/controllers/concerns/table_assigner.rb and app/controllers/tables_controller.rb)
The system offers two algorithms: **Regular Assignment** prioritizes keeping studios together, while **Pack Assignment** maximizes table utilization. Both use:
- **Two-phase algorithm**: Phase 1 groups people into tables, Phase 2 places tables on grid
- **100% success rate** for large studios (>10 people) and studio pairs
- **Event Staff isolation**: Event Staff (studio_id = 0) never mixed with other studios
- **Studio Pair Handling**: Paired studios share tables or are placed adjacent
- **Optimal table utilization**: Fits small studios into existing tables before creating new ones
- **Global position reservation**: Priority system (0-3) ensures complex relationships are preserved
- **Contiguous block placement**: Large studios placed in contiguous blocks for easy identification
- **Smart consolidation**: Combines tables to minimize total count while preserving relationships
- **Studio Proximity**: Manhattan distance calculations for optimal positioning
- Sequential numbering following physical grid layout (row-major order)
- Drag-and-drop grid interface for manual table arrangement
- Handles option tables via person_options join table
