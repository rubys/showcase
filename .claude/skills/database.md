# Database Management

## Standard Database Commands

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

## Running Scripts Against Existing Databases

The `bin/run` command allows you to execute Ruby scripts against any database in the project.

### Basic Usage

```bash
# Run a script file against a specific database
bin/run db/2025-boston.sqlite3 path/to/script.rb

# Evaluate Ruby code directly against a database
bin/run db/2025-boston.sqlite3 -e "puts Event.current.name"

# Run against test database (automatically loads fixtures)
bin/run test -e "puts Person.count"
```

### Common Query Examples

```bash
# Count heats
bin/run db/2025-boston.sqlite3 -e "Heat.count"

# Get all student names
bin/run db/2025-boston.sqlite3 -e "Person.where(type: 'Student').pluck(:name)"

# List studios with person counts
bin/run db/2025-boston.sqlite3 -e "Studio.all.map { |s| [s.name, s.people.count] }"
```

### How bin/run Works

The script automatically sets up:
- `RAILS_APP_DB` environment variable from database filename
- `RAILS_STORAGE` path for Active Storage files
- For test database: runs `db:prepare` and loads fixtures

This allows you to query and manipulate any event database without starting a full Rails server.
