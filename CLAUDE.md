# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

# Run with coverage report (SimpleCov generates /coverage/index.html)
bin/rails test

# Current coverage: ~7.0% (600/8600 lines)
# Comprehensive test coverage for core ballroom dance competition models:
# - HeatScheduler concern (heat scheduling algorithm)
# - Entry model (validation logic, pro-am relationships)  
# - Heat model (basic functionality + scrutineering rules)
# - Person model (STI, validations, billing, name parsing)
# - Score model (judge scoring, JSON handling, scrutineering)
# - Dance model (dance types, categories, multi-dance events)
# - Category model (competition categories, extensions, scheduling)
# - Table model (seating assignments, studio relationships, grid positioning)
# - TablesController (two-phase assignment algorithm achieving 100% success rate)

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

### Asset Management

```bash
# Precompile assets
bin/rails assets:precompile

# Clean old assets
bin/rails assets:clean

# Remove all compiled assets
bin/rails assets:clobber
```

## Architecture Overview

### Multi-tenancy Design
- Each event runs as a separate Rails instance with its own SQLite database
- Phusion Passenger manages multiple instances on a single machine
- NGINX handles routing to the correct instance based on URL patterns
- Shared Redis instance for Action Cable across all events on a machine

### Key Components

1. **Models Structure**
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

2. **Heat Scheduling Algorithm** (app/controllers/concerns/heat_scheduler.rb)
   - Two-pass scheduling: minimize heat count, then balance heat sizes
   - Interleaves different dance types within agenda categories
   - Manual drag-and-drop ordering for solos

3. **Table Assignment Algorithm** (app/controllers/tables_controller.rb)
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

4. **Real-time Updates**
   - Action Cable channels for live score updates
   - Current heat tracking across all ballrooms
   - WebSocket connections managed per event

### Deployment Architecture
- Runs on Fly.io across multiple regions globally
- Each region contains complete copy of all databases
- Automatic rsync backup between regions
- PDF generation runs on separate appliance machines
- Logging aggregated to dedicated logger instances

### Database Schema
- SQLite databases per event (~1MB typical size)
- Volumes for persistent storage
- Automatic backups via rsync to multiple locations
- Daily snapshot backups maintained indefinitely

### Frontend Stack
- Rails 8 with Import Maps (no Node.js build step)
- Stimulus.js for JavaScript behavior
- Turbo for SPA-like navigation
- TailwindCSS for styling
- Custom theme support per event

### Testing Approach
- Standard Rails minitest for unit/integration tests
- System tests using Capybara and Selenium
- Fixtures for test data (test/fixtures/*)
- No separate linting or code style tools configured

## HTML Template Validation Project

### Overview
A comprehensive HTML validation effort is underway to fix structural issues across all ERB templates. A custom ERB-aware validator has been created to identify and fix unclosed tags, mismatched elements, and improper nesting.

### Validation Tool
```bash
# Run the smart ERB-aware HTML validator
ruby bin/validate_html

# The validator is located at lib/html_validator.rb and provides:
# - Context-aware ERB parsing (handles if/else blocks, loops, etc.)
# - Accurate detection of unclosed/mismatched HTML tags
# - Current success rate: 54.7% (122/223 clean files)
```

### Progress Status
**High Priority Files (10+ issues) - COMPLETED:**
- ✅ app/views/solos/critique0.html.erb (24→0 issues)
- ✅ app/views/admin/apply.html.erb (20→0 issues)
- ✅ app/views/scores/heat.html.erb (19→0 issues)
- ✅ app/views/scores/_by_studio.html.erb (18→0 issues)
- ✅ app/views/people/staff.html.erb (17→0 issues)
- ✅ app/views/solos/djlist.html.erb (14→0 issues)
- ✅ app/views/people/index.html.erb (14→0 issues)
- ✅ app/views/studios/_invoice.html.erb (12→0 issues)
- ✅ app/views/heats/index.html.erb (12→0 issues)
- ✅ app/views/people/couples.html.erb (11→0 issues)

**Files to Skip (Word HTML complexity):**
- ⏭️ app/views/solos/critique1.html.erb (Microsoft Word generated)
- ⏭️ app/views/solos/critique2.html.erb (Microsoft Word generated)

**Common Issues Fixed:**
1. Unclosed `<li>` tags in info boxes
2. Unclosed `<th>` and `<td>` tags in tables
3. Mismatched heading tags (e.g., `<h2>` closed with `</h1>`)
4. Missing closing `</tr>` tags in table headers
5. Orphaned closing tags

### Next Steps to Resume
1. Run `ruby bin/validate_html` to see current status
2. Focus on MEDIUM priority files (5-9 issues each)
3. Then tackle LOW priority files (1-4 issues each)
4. Consider implementing HTML validation in CI/CD pipeline
5. Document HTML coding standards for the project

### Tips for Continuing
- The validator may show false positives for complex ERB structures
- Always verify actual structural issues before making changes
- Focus on clear issues like unclosed tags and mismatched elements
- Test thoroughly after fixes - all 645 tests should pass