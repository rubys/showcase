# Navigator - Go Web Server

Navigator is a Go-based replacement for nginx + Phusion Passenger that provides multi-tenant Rails application hosting with on-demand process management.

## Overview

Navigator reads nginx/Passenger configuration files and provides equivalent functionality:
- **Multi-tenant hosting**: Manages multiple Rails applications with separate databases
- **On-demand process management**: Starts Rails apps when needed, stops after idle timeout
- **Static file serving**: Serves assets, images, and static content directly from filesystem
- **Authentication**: Apache MD5 (APR1) htpasswd file support with pattern-based exclusions
- **URL rewriting**: Nginx-style rewrite rules with redirect and last flags
- **Reverse proxy**: Forwards dynamic requests to Rails applications

## Building and Running

```bash
# Build the navigator
make build

# Run with configuration file
./bin/navigator tmp/showcase.conf

# The navigator will:
# - Parse nginx configuration from the specified file
# - Start listening on the configured port (default: 3000)
# - Manage Rails applications on-demand starting from port 4000+
```

## Configuration

Navigator parses nginx configuration files and extracts:

### Server Directives
- `listen 9999` - Port to listen on
- `server_name localhost` - Server name
- `passenger_max_pool_size 54` - Maximum number of Rails processes

### Location Blocks
```nginx
location /showcase/2025/boston/ {
  root /Users/rubys/git/showcase/public;
  passenger_app_group_name showcase-boston-2025;
  passenger_env_var RAILS_APP_DB "2025-boston";
  passenger_env_var RAILS_STORAGE "/path/to/storage";
}
```

### Rewrite Rules
```nginx
rewrite ^/(showcase)?$ /showcase/ redirect;
rewrite ^/assets/ /showcase/assets/ last;
```

### Authentication Patterns
```nginx
if ($request_uri ~ "^/showcase/assets/") { set $realm off; }
auth_basic_user_file /path/to/htpasswd;
```

## Architecture

### Process Management
- **On-demand startup**: Rails apps start when first requested
- **Idle timeout**: Apps automatically shut down after 10 minutes of inactivity
- **Port allocation**: Sequential port assignment starting from 4000
- **Environment variables**: Passed from configuration to Rails processes

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
- **Auto-extension detection**: `/showcase/studios/raleigh` → `raleigh.html`
- **Extension priority**: `.html`, `.htm`, `.txt`, `.xml`, `.json`
- **Fallback to Rails**: If no static file found, proxies to Rails application
- **Content-Type detection**: Automatic MIME type setting based on file extension

### Authentication
- **Apache MD5 (APR1)**: Full implementation of htpasswd hash verification
- **Pattern-based exclusions**: Regex patterns for public paths
- **Basic Auth**: Standard HTTP Basic Authentication

### Request Flow
1. **Rewrite rules**: Applied first for redirects and path modifications
2. **Authentication**: Checked against patterns and htpasswd file
3. **Static files**: Attempted if path matches static patterns (assets, explicit extensions)
4. **Try files**: For non-authenticated routes, attempts to find static files with common extensions
5. **Rails proxy**: Falls back to starting/proxying to Rails application

## Key Features

### Configuration-Driven
- **No recompilation needed**: All patterns parsed from config file
- **Dynamic reloads**: Restart navigator to pick up config changes
- **Nginx compatibility**: Reads standard nginx configuration syntax

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

### Key Functions
- `ParseConfig()` - Parses nginx configuration files
- `serveStaticFile()` - Handles static file serving for assets and explicit extensions
- `tryFiles()` - Implements nginx-style try_files for non-authenticated routes
- `handleRewrites()` - Processes URL rewrite rules
- `shouldExcludeFromAuth()` - Checks authentication exclusion patterns
- `NewAppManager()` - Manages Rails application lifecycle

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

## Nginx Equivalent

Navigator's try_files implementation is equivalent to nginx configuration like:

```nginx
location /showcase/studios/ {
    auth_basic off;
    try_files $uri $uri.html $uri.htm $uri.txt $uri.xml $uri.json @rails;
}

location /showcase/regions/ {
    auth_basic off;
    try_files $uri $uri.html $uri.htm $uri.txt $uri.xml $uri.json @rails;
}

location @rails {
    proxy_pass http://rails_app;
}
```

This provides zero Rails overhead for public content while maintaining security for protected routes.