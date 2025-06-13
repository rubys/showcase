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

# Current coverage: ~4.0% (331/8336 lines)
# Comprehensive test coverage for core ballroom dance competition models:
# - HeatScheduler concern (heat scheduling algorithm)
# - Entry model (validation logic, pro-am relationships)  
# - Heat model (basic functionality + scrutineering rules)
# - Person model (STI, validations, billing, name parsing)
# - Score model (judge scoring, JSON handling, scrutineering)
# - Dance model (dance types, categories, multi-dance events)
# - Category model (competition categories, extensions, scheduling)

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

2. **Heat Scheduling Algorithm** (app/controllers/concerns/heat_scheduler.rb)
   - Two-pass scheduling: minimize heat count, then balance heat sizes
   - Interleaves different dance types within agenda categories
   - Manual drag-and-drop ordering for solos

3. **Real-time Updates**
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