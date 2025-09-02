# Navigator - Go Web Server

Navigator is a Go-based web server that provides multi-tenant Rails application hosting with on-demand process management.

## Overview

Navigator uses YAML configuration format for:
- **Multi-tenant hosting**: Manages multiple Rails applications with separate databases
- **On-demand process management**: Starts Rails apps when needed, stops after idle timeout
- **Managed processes**: Start and stop additional processes alongside Navigator (Redis, workers, etc.)
- **Static file serving**: Serves assets, images, and static content directly from filesystem with configurable caching
- **Authentication**: Full htpasswd support (APR1, bcrypt, SHA, etc.) with pattern-based exclusions
- **URL rewriting**: Rewrite rules with redirect, last, and fly-replay flags
- **Reverse proxy**: Forwards dynamic requests to Rails applications with method-based exclusions
- **Machine suspension**: Auto-suspend Fly.io machines after idle timeout (when enabled)
- **Configuration reload**: Live configuration reload with SIGHUP signal (no restart needed)
- **YAML configuration**: Modern YAML-based configuration format

## Building and Running

```bash
# Build the navigator
make build
# Or build directly with Go
go build -mod=readonly -o bin/navigator cmd/navigator/main.go

# Display help
./bin/navigator --help

# Run with YAML configuration (default location)
./bin/navigator
# Or specify a custom config file
./bin/navigator config/navigator.yml

# Reload configuration without restart
./bin/navigator -s reload
# Or send SIGHUP signal directly
kill -HUP $(cat /tmp/navigator.pid)

# Helper script for production mode with automatic setup
bin/nav  # Sets RAILS_ENV=production, precompiles assets, generates config, opens browser

# Generate/regenerate the YAML configuration (config/navigator.yml)
# NOTE: Always regenerate after modifying configurator.rb - never edit the YAML directly!
bin/rails nav:config
# Or with full preparation (assets, prerender, config)
bin/rails nav:prep

# The navigator will:
# - Auto-detect configuration format (YAML vs nginx)
# - Start listening on the configured port (default: 9999 for local, 3000 for production)
# - Dynamically allocate ports for Rails applications (4000-4099)
# - Clean up stale PID files before starting apps
# - Handle graceful shutdown on interrupt signals
```

## Configuration Format

### YAML Configuration

**⚠️ IMPORTANT**: `config/navigator.yml` is a generated file. DO NOT edit it directly!
- To modify configuration: Edit `app/controllers/concerns/configurator.rb`
- To regenerate: Run `bin/rails nav:config`
- Changes to the YAML file will be lost on next generation

The YAML configuration is automatically generated from your Rails application settings:

```yaml
server:
  listen: 3000
  hostname: localhost
  root_path: /showcase
  public_dir: /path/to/public

pools:
  max_size: 22
  idle_timeout: 300
  start_port: 4000

auth:
  enabled: true
  realm: Showcase
  htpasswd: /path/to/htpasswd
  public_paths:
    - /showcase/assets/
    - /showcase/docs/
    - "*.css"
    - "*.js"

static:
  directories:
    - path: /showcase/assets/
      root: assets/
      cache: 86400
  extensions: [html, htm, css, js, png, jpg, gif]
  try_files:
    enabled: true
    suffixes: ["index.html", ".html", ".htm", ".txt", ".xml", ".json"]
    fallback: rails

applications:
  global_env:
    RAILS_RELATIVE_URL_ROOT: /showcase
  
  # Standard environment variables applied to all tenants (except special ones)
  standard_vars:
    RAILS_APP_DB: "${tenant.database}"
    RAILS_APP_OWNER: "${tenant.owner}"  # Studio name only
    RAILS_STORAGE: "/path/to/storage"   # Root storage path (not tenant-specific)
    RAILS_APP_SCOPE: "${tenant.scope}"
    PIDFILE: "/path/to/pids/${tenant.database}.pid"
  
  tenants:
    - name: 2025-boston
      path: /showcase/2025/boston/
      group: showcase-2025-boston
      database: 2025-boston
      owner: "Boston Dance Studio"
      storage: "/path/to/storage/2025-boston"
      scope: "2025/boston"
      env:
        SHOWCASE_LOGO: "boston-logo.png"
    
    # Special tenants that don't use standard_vars
    - name: cable
      path: /cable
      group: showcase-cable
      special: true
      force_max_concurrent_requests: 0
    
    # Tenants with pattern matching for WebSocket support
    - name: cable-pattern
      path: /cable-specific
      group: showcase-cable
      match_pattern: "*/cable"  # Matches any path ending with /cable
      special: true
    
    # Tenants with standalone servers (e.g., Action Cable)
    - name: external-service
      path: /external/
      standalone_server: "localhost:28080"  # Proxy to standalone server instead of Rails

managed_processes:
  - name: redis
    command: redis-server
    args: []
    working_dir: /path/to/app
    env:
      REDIS_PORT: "6379"
    auto_restart: true
    start_delay: 0
    
  - name: sidekiq
    command: bundle
    args: [exec, sidekiq]
    working_dir: /path/to/app
    env:
      RAILS_ENV: production
    auto_restart: true
    start_delay: 2

# Machine suspension (Fly.io specific)
suspend:
  enabled: false
  idle_timeout: 600  # Seconds of inactivity before suspending machine

# Routing enhancements
routes:
  # Fly-replay support for multi-target routing
  fly_replay:
    # App-based routing (route to any instance of smooth-pdf app)
    - path: "^/showcase/.+\\.pdf$"
      app: smooth-pdf
      status: 307
    
    # Machine-based routing (route to specific machine instance)
    - path: "^/showcase/priority/.+\\.pdf$"
      machine: "48e403dc711e18"
      app: smooth-pdf
      status: 307
    
    # Region-based routing (route to specific region)
    - path: "^/showcase/2025/sydney/"
      region: syd
      status: 307
      methods: [GET]
  
  # Reverse proxy with method exclusions
  reverse_proxies:
    - path: "/api/"
      target: "http://api.example.com"
      headers:
        X-API-Key: "secret"
      exclude_methods: [POST, DELETE]  # Don't proxy these methods
```

## Architecture

### Managed Processes

Navigator can manage additional processes that should run alongside the web server. These processes are:
- **Started automatically** when Navigator starts
- **Stopped gracefully** when Navigator shuts down (after Rails apps to maintain dependencies)
- **Monitored and restarted** if they crash (when auto_restart is enabled)
- **Started with delays** to ensure proper initialization order

Configuration options for each managed process:
- `name`: Unique identifier for the process
- `command`: The executable to run
- `args`: Array of command-line arguments
- `working_dir`: Directory to run the process in
- `env`: Environment variables to set for the process
- `auto_restart`: Whether to restart the process if it exits unexpectedly
- `start_delay`: Seconds to wait before starting this process

Common use cases:
- **Redis server**: Cache and session storage
- **Sidekiq/Resque**: Background job processors
- **WebSocket servers**: Additional real-time communication servers
- **Monitoring scripts**: Health check and metrics collection
- **File watchers**: Asset compilation or file synchronization

The managed processes configuration is generated by `configurator.rb` based on environment variables:
- `START_REDIS=true`: Starts a Redis server
- `START_WORKER=true`: Starts a Sidekiq worker
- `START_MONITOR=true`: Starts a custom monitoring script

### Process Management
- **On-demand startup**: Rails apps start when first requested
- **Idle timeout**: Apps automatically shut down after 5 minutes of inactivity (configurable)
- **Dynamic port allocation**: Finds available ports in range 4000-4099 instead of sequential assignment
- **PID file management**: Cleans up stale PID files before starting and after stopping apps
- **Graceful shutdown**: Handles SIGINT/SIGTERM signals to cleanly stop all Rails apps
- **Environment variables**: Inherits from parent process and adds configuration variables
- **Process cleanup**: Automatically removes PID files and kills stale processes

### Static File Serving
Serves files directly from filesystem for performance:
- **Assets**: `/assets/` → `public/assets/`
- **Images**: `*.png`, `*.jpg`, `*.gif` → `public/`
- **Documentation**: `/docs/` → `public/docs/`
- **Regions**: `/regions/` → `public/regions/`
- **Studios**: `/studios/` → `public/studios/`
- **Fonts**: `/fonts/` → `public/fonts/`

### Try Files Behavior
For non-authenticated routes, implements nginx-style `try_files` behavior:
- **Directory index support**: `/showcase/studios/` → `studios/index.html`
- **Auto-extension detection**: `/showcase/studios/raleigh` → `raleigh.html`
- **Extension priority**: `index.html`, `.html`, `.htm`, `.txt`, `.xml`, `.json`
- **Fallback to Rails**: If no static file found, proxies to Rails application
- **Content-Type detection**: Automatic MIME type setting based on file extension

### Authentication
- **Multiple formats**: Full htpasswd support via go-htpasswd library (APR1, bcrypt, SHA, MD5-crypt, etc.)
- **Pattern-based exclusions**: Simple glob patterns and regex patterns for public paths
- **Basic Auth**: Standard HTTP Basic Authentication

### Request Flow
1. **Suspend tracking**: Track request start/finish for idle detection (Fly.io only)
2. **Rewrite rules**: Applied first for redirects, path modifications, and fly-replay
3. **Authentication**: Checked against patterns and htpasswd file
4. **Static files**: Attempted if path matches static patterns (assets, explicit extensions)
5. **Try files**: For non-authenticated routes, attempts to find static files with common extensions
6. **Proxy routes**: Check for reverse proxy configurations with method exclusions
7. **Location matching**: Find best match using pattern matching or prefix matching
8. **Standalone servers**: Proxy to external servers if configured
9. **Rails proxy**: Falls back to starting/proxying to Rails application

## Key Features

### Configuration-Driven
- **No recompilation needed**: All patterns parsed from config file
- **Generated YAML**: Configuration is generated from Rails settings via `configurator.rb`
- **Dynamic reloads**: Regenerate config with `bin/rails nav:config` and restart navigator

### Performance Optimizations
- **Static file serving**: Bypasses Rails for assets and static content
- **Try files optimization**: Serves public content (studios, regions, docs) without Rails
- **Process pooling**: Reuses Rails processes across requests
- **Concurrent handling**: Multiple requests processed simultaneously
- **Proper content types**: Automatic MIME type detection
- **Zero Rails overhead**: Public routes serve static files instantly

### Rails Compatibility
- **Full path preservation**: Rails receives complete URL paths for routing
- **Environment variables**: All passenger_env_var directives passed through
- **Process lifecycle**: Proper startup, shutdown, and error handling
- **Request headers**: X-Forwarded-* headers set correctly

## Development

### File Structure
- `cmd/navigator/main.go` - Main application entry point
- `Makefile` - Build configuration
- `go.mod`, `go.sum` - Go module dependencies

### Logging
Navigator uses Go's `slog` package for structured logging:
- **Log Level**: Set via `LOG_LEVEL` environment variable (debug, info, warn, error)
- **Default Level**: Info level if not specified
- **Debug Output**: Includes detailed request routing, auth checks, and file serving attempts
- **Structured Format**: Text handler with consistent key-value pairs

### Key Functions
- `LoadConfig()` - Loads YAML configuration
- `ParseYAML()` - Parses YAML configuration with template variable substitution
- `cleanupPidFile()` - Checks for and removes stale PID files
- `findAvailablePort()` - Finds available ports dynamically instead of sequential assignment
- `UpdateConfig()` - Updates configuration without restart (via SIGHUP)
- `NewAppManager()` - Manages Rails application lifecycle with improved cleanup
- `NewProcessManager()` - Manages external processes with auto-restart capability
- `NewSuspendManager()` - Handles Fly.io machine suspension after idle timeout
- `serveStaticFile()` - Handles static file serving for assets and explicit extensions
- `tryFiles()` - Implements try_files with index.html support
- `handleRewrites()` - Processes URL rewrite rules including fly-replay
- `shouldExcludeFromAuth()` - Checks authentication exclusion patterns
- `sendReloadSignal()` - Sends SIGHUP to reload configuration without restart

### Testing
```bash
# Test static asset serving
curl -I http://localhost:9999/showcase/assets/application.js

# Test try_files behavior (non-authenticated routes)
curl -I http://localhost:9999/showcase/studios/raleigh        # → raleigh.html
curl -I http://localhost:9999/showcase/regions/dfw           # → dfw.html

# Test authentication
curl -u username:password http://localhost:9999/protected/path

# Test Rails proxy (authenticated routes)
curl -u test:secret http://localhost:9999/showcase/2025/boston/
```

## Recent Improvements (August-December 2025)

### Machine Suspension Support (New - December 2025)
- **Fly.io Integration**: Auto-suspend machines after configurable idle timeout
- **Request Tracking**: Monitors active requests to determine idle state
- **Automatic Wake**: Machines wake automatically on incoming requests
- **Configurable Timeout**: Set idle timeout duration in YAML configuration

### Configuration Reload (New - December 2025)
- **Live Reload**: Reload configuration without restart using SIGHUP signal
- **Reload Command**: Support for `navigator -s reload` command
- **PID File Management**: Writes PID file to /tmp/navigator.pid for signal management
- **Atomic Updates**: Configuration changes applied atomically with no downtime

### Fly-Replay Support (New - December 2025)
- **Multi-Target Routing**: Support for three routing types:
  - **App-based**: Route to any instance of a specific app (e.g., `smooth-pdf`)
  - **Machine-based**: Route to a specific machine instance using `prefer_instance`
  - **Region-based**: Route to a specific Fly.io region
- **Pattern Matching**: Configure URL patterns for targeted routing
- **Status Codes**: Configurable HTTP status codes for replay responses
- **Method Filtering**: Apply replay rules only to specific HTTP methods
- **Fallback Proxy**: Automatic reverse proxy when fly-replay constraints prevent direct routing
- **Internal Networking**: Support for `.internal`, `.vm.app.internal`, and regional `.internal` URLs

### Reverse Proxy Enhancements (New - December 2025)
- **Method Exclusions**: Exclude specific HTTP methods from proxy routing
- **Custom Headers**: Add headers to proxied requests
- **Multiple Targets**: Support for multiple proxy configurations

### Standalone Server Support (New - November 2025)
- **External Services**: Proxy to standalone servers (e.g., Action Cable)
- **Pattern Matching**: Use wildcard patterns for location matching
- **WebSocket Support**: Full support for WebSocket connections

### Managed Processes Feature (New - August 2025)
- **External Process Management**: Navigator can now start and stop additional processes defined in configuration
- **Auto-restart Capability**: Processes can be configured to automatically restart if they crash
- **Startup Delays**: Processes can be delayed to ensure proper initialization order
- **Environment Variables**: Each process can have custom environment variables
- **Graceful Shutdown**: Rails apps stopped first, then managed processes (preserving dependencies)
- **Configuration Updates**: Managed processes updated on configuration reload

### Process Management Enhancements
- **PID File Handling**: Navigator now checks for and cleans up stale PID files before starting Rails apps, preventing "server is already running" errors
- **Dynamic Port Allocation**: Instead of sequential port assignment (4000, 4001, 4002...), Navigator finds available ports dynamically, avoiding port conflicts
- **Graceful Shutdown**: Added signal handling for SIGINT/SIGTERM with proper cleanup of all Rails processes and PID files
- **Environment Variable Inheritance**: Rails apps inherit parent process environment variables (e.g., RAILS_ENV)

### Configuration Improvements
- **Directory Index Support**: Added `index.html` to try_files suffixes for proper directory serving
- **RAILS_STORAGE Fix**: Changed to use root storage path instead of tenant-specific paths
- **RAILS_APP_OWNER Fix**: Now uses studio name only instead of "Studio - Event" format
- **Helper Script**: Added `bin/nav` for easy production mode startup with automatic setup

### Rails Integration
- **Rake Tasks**: `nav:config` generates YAML configuration, `nav:prep` does full preparation
- **Configurator Module**: `app/controllers/concerns/configurator.rb` generates Navigator YAML configuration
- **PIDFILE Support**: Automatically configured for each tenant in standard_vars
- **Generated Configuration**: `config/navigator.yml` is generated - modify `configurator.rb` and regenerate instead of editing directly

## Deployment

Navigator is designed to replace nginx + Passenger in production environments:
- **Single binary**: No external dependencies
- **Configuration compatibility**: Uses existing nginx config files
- **Resource efficiency**: Lower memory footprint than full nginx/Passenger stack
- **Monitoring**: Built-in logging for requests, static files, and process management

## Limitations

- **Single-threaded config parsing**: Configuration loaded once at startup
- **No SSL termination**: Designed to run behind load balancer/CDN
- **SQLite focus**: Optimized for SQLite-based multi-tenant applications
- **Basic proxy features**: Supports essential reverse proxy functionality
- **Try files scope**: Only applies to non-authenticated routes for security

## Try Files Behavior

Navigator's try_files implementation attempts to serve static files with various extensions before falling back to Rails:
- Tries: `$uri`, `$uri.html`, `$uri.htm`, `$uri.txt`, `$uri.xml`, `$uri.json`
- Falls back to Rails application if no static file found
- Provides zero Rails overhead for public content while maintaining security for protected routes

## Future Implementation Ideas

The following features are planned for future development to enhance Navigator's capabilities:

### 1. Complete Go Library Refactoring
- **Router improvements**: Replace basic `http.ServeMux` with `chi` router (already in go.mod) for better routing patterns and middleware support
- **Configuration management**: Add `viper` or `koanf` for more flexible configuration handling and validation
- **Static serving middleware**: Use `chi/middleware` for enhanced static file handling with better caching controls

### 2. Missing YAML Feature Implementation
Several YAML configuration fields are parsed but not yet fully utilized:
- **Health check configuration**: Make health endpoint configurable beyond hardcoded `/up`
- **Logging configuration**: Implement log level and format settings from YAML
- **Process management**: Enforce min_instances setting for critical applications
- **Cache headers**: Full implementation of TTL configuration for static file caching

### 3. Developer Experience Improvements
- **Configuration validation**: Validate YAML configuration on startup with helpful error messages
- **Hot reload**: Watch YAML configuration file and reload without restart
- **Debug modes**: Add verbose logging modes and metrics endpoint for troubleshooting
- **Configuration testing**: Tool to test configuration without starting full server

### 4. Documentation and Best Practices
- **Configuration validation**: Tool to test configuration without starting full server
- **Documentation updates**: Comprehensive deployment documentation
- **Best practices guide**: Guide for optimal configuration patterns

### 5. Production Readiness Enhancements
- ~~**Graceful shutdown**: Proper SIGTERM handling for zero-downtime deployments~~ ✅ Implemented
- ~~**External process management**: Start/stop additional processes with Navigator~~ ✅ Implemented
- ~~**Configuration reload**: Live configuration updates without restart~~ ✅ Implemented
- ~~**Machine suspension**: Auto-suspend idle Fly.io machines~~ ✅ Implemented
- **Connection pooling**: Improved HTTP client management for Rails application proxying
- **Error handling**: More robust error responses, recovery mechanisms, and structured logging
- **Monitoring**: Built-in metrics collection and health monitoring capabilities

### 6. Rails Integration Improvements
- **Automatic generation**: Have Rails automatically call `generate_navigator_config` during deployment
- **Deployment automation**: Update deployment scripts to use YAML format by default
- **Performance monitoring**: Add request/response metrics and Rails application performance tracking
- **Dynamic configuration**: Allow Rails to update Navigator configuration without restart

### 7. Advanced Features
- **Load balancing**: Support for multiple Rails backend instances per tenant
- **SSL termination**: Optional SSL/TLS support for development environments
- **Rate limiting**: Request rate limiting per tenant or globally
- **Request routing**: Advanced routing based on headers, query parameters, or custom logic

These improvements would make Navigator a more complete, production-ready web server while maintaining its focus on simplicity and performance for Rails multi-tenant applications.