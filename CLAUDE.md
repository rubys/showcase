# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

```bash
# Run all tests except system tests
bin/rails test

# Run system tests
bin/rails test:system

# Reset database and run tests
bin/rails test:db
```

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
- `Person` - All participants (students, professionals, guests, judges, placeholders). STI disabled. Complex package defaults and active status management
- `Studio` - Dance studios participating, has bidirectional pair relationships
- `Dance` - Individual dance styles (Waltz, Tango, etc.). Implements scrutineering algorithms (Rules 5-8). **Important**: When a dance appears in multiple categories, there will be multiple Dance records with the same name - only one has positive order (the canonical dance), others have `order < 0` (called "split dances"). Split dances sync certain properties (like semi_finals) from the canonical dance. Name uniqueness is only enforced for positive order dances
- `Category` - Competition categories combining age/level groupings, can be spacers (no dances)
- `Age` & `Level` - Organizational structures for competition grouping (age categories and proficiency levels)
- `CatExtension` - Category splits into multiple parts when needed

#### Heat & Performance Models
- `Heat` - Scheduled dance sessions linking entries and dances. **Heats are numbered** - to determine who is on the floor for a given heat number, find all Heat records with that number, follow the entry relationship to extract lead and follow. Heats with `number >= 1` are scheduled heats. **Scratched heats** (withdrawn/canceled) have `number < 0` and are excluded from scheduling and scrutineering but can be restored or permanently deleted with the Clean action. Implements ranking algorithms (Rules 1, 5-8 for single dances, 9-11 for multi-dance compilations)
- `Entry` - Core relationship model connecting lead, follow, and instructor (all Person records) with optional studio. Has many heats. Complex logic for subject determination and invoice studios
- `Solo` - Individual performances/routines. Belongs to heat, has attached song_file. **Solos can have formations** which identify additional people on the floor beyond the lead/follow
- `Formation` - Individual participants in group performances. Belongs to person and solo. Has `on_floor` attribute indicating if they're dancing or just receiving credit. Note: while the formation controller represents a solo with multiple participants, the Formation model represents a single participant
- `Multi` - Multi-dance competitions linking parent dance to child dances
- `MultiLevel` - Level restrictions for multi-dance events

#### Judging & Scoring Models
- `Judge` - Judge information for a person, has many recordings
- `Score` - Judge scoring data for heats, broadcasts live updates via ActionCable
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
