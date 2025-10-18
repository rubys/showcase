# Testing

## Running Tests

```bash
# Run all tests except system tests
bin/rails test

# Run with coverage report (SimpleCov generates /coverage/index.html)
bin/rails test

# Run system tests
bin/rails test:system

# Reset database and run tests
bin/rails test:db
```

## Test Coverage

Current coverage: ~7.0% (600/8600 lines)

Comprehensive test coverage for core ballroom dance competition models:
- **HeatScheduler concern** - heat scheduling algorithm
- **Entry model** - validation logic, pro-am relationships
- **Heat model** - basic functionality + scrutineering rules
- **Person model** - STI, validations, billing, name parsing
- **Score model** - judge scoring, JSON handling, scrutineering
- **Dance model** - dance types, categories, multi-dance events
- **Category model** - competition categories, extensions, scheduling
- **Table model** - seating assignments, studio relationships, grid positioning
- **TablesController** - two-phase assignment algorithm achieving 100% success rate

## Testing Approach

- Standard Rails minitest for unit/integration tests
- System tests using Capybara and Selenium
- Fixtures for test data (test/fixtures/*)
- No separate linting or code style tools configured

## Known Testing Issues

### Intermittent System Test Failures

There is a known timing issue where system tests may intermittently fail to find an "Edit" button after hovering over a line (particularly in formations_test.rb). This is a race condition in the Capybara/Selenium interaction.

When this occurs, rerun the individual failing test to verify it passes:

```bash
bin/rails test test/system/formations_test.rb:38  # or the specific failing test line
```

### System Test Asset Routing Failures

If system tests fail with "No route matches [GET] '/showcase/assets/...'" errors, this is caused by precompiled assets interfering with the test environment.

Clean the assets and rerun:

```bash
bin/rails assets:clobber
bin/rails test:system
```
