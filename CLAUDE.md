# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Claude Code Skills

This project includes custom skills in `.claude/skills/` that provide specialized guidance:

- **fly-ssh.md** - Best practices for using `fly ssh console` (no pipes, Debian syntax, direct commands only)
- **database.md** - Database management and `bin/run` usage patterns
- **deployment.md** - Deployment architecture and multi-tenancy patterns
- **testing.md** - Testing procedures, coverage, and known issues
- **render-page.md** - Page rendering and view testing guidance

**Note:** Skills may not be automatically loaded in all Claude Code sessions. If the `<available_skills>` section is empty, read skill files directly for guidance rather than attempting to invoke them as tools.

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

For detailed testing information including coverage reports and known issues, see the `testing` skill.

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

For information about running scripts against existing databases, see the `database` skill.

## Key Components

### Models Structure
- `Event` - Singleton configuration for each showcase
- `Person` - Participants (judges, instructors, students, guests)
- `Studio` - Dance studios participating
- `Dance` - Individual dance styles
- `Category` - Competition categories combining age/level
- `Heat` - Scheduled dance sessions
- `Solo` - Individual performances
- `Formation` - Group performances
- `Multi` - Multi-dance competitions
- `Score` - Judge scoring data
- `Table` - Seating table management with grid positioning
- `StudioPair` - Paired studio relationships for table proximity

### Heat Scheduling Algorithm (app/controllers/concerns/heat_scheduler.rb)
- Two-pass scheduling: minimize heat count, then balance heat sizes
- Interleaves different dance types within agenda categories
- Manual drag-and-drop ordering for solos

### Table Assignment Algorithm (app/controllers/tables_controller.rb)
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

## Additional Information

For detailed information about:
- **Testing procedures and known issues** - use the `testing` skill
- **Database management and bin/run usage** - use the `database` skill
- **Deployment architecture and multi-tenancy** - use the `deployment` skill

