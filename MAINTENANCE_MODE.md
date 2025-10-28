# Maintenance Mode Guide

This document explains how maintenance mode works in the Navigator-managed showcase application.

## Overview

Maintenance mode allows you to perform application updates, database migrations, or other maintenance tasks while keeping infrastructure and static content accessible.

## What Continues Working During Maintenance

When maintenance mode is enabled (`maintenance.enabled: true`), the following continue to function normally:

### Infrastructure Components

1. **Authentication**
   - htpasswd authentication remains active
   - Public paths configured in `auth.public_paths` remain accessible
   - Protected resources still require credentials

2. **Static Files**
   - All files matching `allowed_extensions` are served directly
   - Extensions: `html, htm, txt, xml, json, css, js, png, jpg, gif, svg, ico, pdf, xlsx`
   - Includes pre-rendered studio pages, documentation, and assets

3. **Try Files**
   - Extensionless URLs resolved with try_files extensions
   - Examples: `/studios/raleigh` → `/studios/raleigh.html`
   - Configured extensions: `index.html, .html, .htm, .txt, .xml, .json`

### Routing & Proxying

4. **Redirects**
   - All configured redirects continue working
   - Example: `/` → `/showcase/studios/`
   - Users get consistent navigation experience

5. **URL Rewrites**
   - Asset path normalization continues
   - Example: `/assets/*` → `/showcase/assets/*`
   - Ensures static assets load correctly

6. **Reverse Proxies**
   - Password management proxy to rubix
   - Studio request proxy to rubix
   - Remote services remain operational

7. **CGI Scripts**
   - Configuration update endpoint (`/showcase/update_config`)
   - Allows remote configuration updates during maintenance
   - Can reload configuration without container restart
   - Useful for exiting maintenance mode remotely

8. **Health Checks** (`/up`)
   - Synthetic health check returns 200 OK
   - No Rails application required
   - Keeps containers healthy during maintenance
   - Load balancers continue routing

## What Doesn't Work During Maintenance

The following features are intentionally disabled during maintenance mode:

1. **Action Cable WebSocket Connections**
   - Real-time updates not available
   - No managed Action Cable process running
   - No WebSocket proxy configured

2. **Dynamic Rails Application Requests**
   - All tenant application routes blocked
   - Only static pre-rendered content accessible

3. **Fly-Replay Routes**
   - PDF generation not available
   - XLSX generation not available
   - Cross-region routing disabled

## What Shows Maintenance Page

**Only**: Dynamic requests to Rails tenant applications

When a request reaches the web application proxy phase (after all static/infrastructure handlers), users see the configured maintenance page (`public/503.html`).

### Example Scenarios

✅ **Available during maintenance:**
- `/showcase/studios/` - Pre-rendered studio index (static HTML)
- `/showcase/studios/raleigh.html` - Pre-rendered studio page
- `/showcase/assets/application.css` - Static assets
- `/showcase/docs/` - Static documentation
- `/up` - Health check (synthetic 200 OK response)
- `/showcase/update_config` - CGI configuration endpoint (POST)

❌ **Shows maintenance page:**
- `/showcase/2025/boston/` - Dynamic Rails tenant request
- `/showcase/2025/boston/heats` - Dynamic Rails tenant request
- `/showcase/2025/boston/scores` - Dynamic Rails tenant request

❌ **Not available (disabled during maintenance):**
- `/showcase/cable` - Action Cable WebSocket connections
- `/showcase/2025/boston/invoice.pdf` - PDF generation (Fly-Replay routes not configured)

## Configuration Generation

**IMPORTANT**: The maintenance configuration file (`config/navigator-maintenance.yml`) is **automatically generated** from the same `Configurator` module that builds the full navigator config. This ensures it always stays in sync with your infrastructure.

### How Generation Works

The maintenance config is generated using:

```bash
# Manually generate (for testing)
bundle exec rake nav:maintenance

# Or directly via script
ruby script/generate_navigator_config.rb --maintenance
```

**During Docker build**, the maintenance config is automatically generated and baked into the image:

```dockerfile
# From Dockerfile.nav
RUN SECRET_KEY_BASE=DUMMY RAILS_ENV=production \
    bundle exec rake nav:maintenance
```

### What Gets Generated

The maintenance config includes essential infrastructure from `Configurator` module:

1. **server** - Full server config:
   - root_path, static files, cache_control
   - **CGI scripts** - Configuration update endpoint (`/showcase/update_config`)
   - **health_check** - Synthetic health check at `/up` (returns 200 OK)
2. **managed_processes** - Empty array (no processes started during maintenance)
3. **routes** - Infrastructure routes only:
   - Redirects for user-friendly navigation
   - Rewrites for asset path normalization
   - Remote service reverse proxies (password, studios request)
   - **Excludes**: Action Cable WebSocket proxy (not needed during maintenance)
4. **auth** - Authentication with public paths and **critical root path exemption** (`^/$`)
5. **maintenance.enabled: true** - Enables maintenance mode
6. **hooks** - Only ready hook for initialization (runs `script/nav_initialization.rb`)
7. **logging** - Text format for easier debugging during startup

**Key differences from full config**:
- No `applications` or `tenants` sections
- No managed processes (no Action Cable, no Redis)
- No Action Cable WebSocket proxy
- No Fly-Replay routes
- Synthetic health check instead of Rails health endpoint

### Critical Auth Pattern

The generated config automatically includes this critical auth pattern:

```yaml
auth_patterns:
  - pattern: "^/$"
    action: 'off'
```

**Why this matters**: Authentication happens BEFORE redirects in Navigator's request flow. Without this exemption, the root path requires authentication and users get `401 Unauthorized` instead of being redirected to `/showcase/studios/`.

### Benefits of Auto-Generation

✅ **Always in sync** - Changes to `Configurator` automatically flow to maintenance config
✅ **No manual maintenance** - Config is generated during build
✅ **Single source of truth** - All config logic in one place
✅ **No git tracking** - `config/navigator-maintenance.yml` is in `.gitignore`
✅ **DRY principles** - Shared methods eliminate duplication between full and maintenance configs

### Implementation Details

The `Configurator` module uses shared builder methods to ensure consistency:

- **`build_server_config_base`**: Core server configuration (listen, hostname, static files, health check)
- **`build_static_config`**: Static file configuration (extensions, try_files, cache control)
- **`build_public_paths`**: Public paths list for authentication
- **`build_health_check_config`**: Synthetic health check response

Both full and maintenance configs use these shared methods with different parameters:
- Full config: Environment-detected values (hostname, port, paths)
- Maintenance config: Hardcoded production values (localhost:3000, /showcase, /rails)

This approach discovered during refactoring ensures:
- Consistent behavior between configs
- Easier maintenance and updates
- Reduced code duplication
- Clear separation between environment-specific and shared configuration

## Enabling Maintenance Mode

### Method 1: Configuration Reload (Recommended)

1. Start with `config/navigator-maintenance.yml`:
```yaml
maintenance:
  enabled: true
  page: /503.html
```

2. After maintenance, reload with `config/navigator.yml`:
```bash
# Via CGI endpoint (preferred for remote deployments)
curl -X POST https://your-app.fly.dev/showcase/update_config

# Via signal (local/SSH access)
kill -HUP $(cat /tmp/navigator.pid)
```

### Method 2: Direct Configuration Edit

Edit `config/navigator.yml`:
```yaml
maintenance:
  enabled: true  # Set to true for maintenance
  page: /503.html
```

Then reload:
```bash
kill -HUP $(cat /tmp/navigator.pid)
```

## Maintenance Page Design

The maintenance page at `public/503.html` should include:

1. **Auto-refresh**: Automatically reloads when maintenance completes
2. **Clear messaging**: Explains the situation to users
3. **Estimated time**: If known, provide expected completion time
4. **Static resources**: Uses only inline CSS (no external assets)

Example:
```html
<!DOCTYPE html>
<html>
<head>
  <title>Maintenance in Progress</title>
  <meta http-equiv="refresh" content="5">  <!-- Auto-refresh every 5 seconds -->
  <style>
    body {
      font-family: system-ui;
      text-align: center;
      padding: 50px;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
    }
  </style>
</head>
<body>
  <h1>Maintenance in Progress</h1>
  <p>We're currently performing scheduled maintenance.</p>
  <p>The application will return automatically when maintenance completes.</p>
  <p>This page refreshes every 5 seconds.</p>
</body>
</html>
```

## Best Practices

### 1. Pre-render Static Content

Before enabling maintenance mode, ensure critical pages are pre-rendered:
```bash
bin/rails prerender:studios
bin/rails prerender:public_pages
```

This allows users to access key information during maintenance.

### 2. Use Ready Hooks for Zero-Downtime Updates

Start with maintenance mode, then switch to normal operation:

```yaml
# config/navigator-maintenance.yml
maintenance:
  enabled: true

hooks:
  server:
    ready:
      - command: ruby
        args: [script/run_migrations.rb]
        timeout: 5m
        reload_config: config/navigator.yml  # Switch to normal config
```

**Flow:**
1. Navigator starts with maintenance mode enabled
2. Static content accessible immediately
3. Ready hook runs migrations in background
4. On success, reloads to normal configuration
5. Full application access restored

### 3. Test Maintenance Mode Locally

```bash
# Start with maintenance config
bin/navigator config/navigator-maintenance.yml

# Verify static files work
curl http://localhost:9999/showcase/studios/

# Verify dynamic requests get maintenance page
curl http://localhost:9999/showcase/2025/boston/

# Reload to normal config
kill -HUP $(cat /tmp/navigator.pid)
```

### 4. Monitor During Maintenance

Health checks continue working during maintenance:
- `/up` returns synthetic 200 OK response
- No Rails application required
- Containers stay healthy
- Load balancers continue routing
- Monitoring systems don't alert during maintenance

## Troubleshooting

### Static Files Not Serving

Check configuration:
```yaml
server:
  static:
    public_dir: public
    allowed_extensions: [html, htm, txt, xml, json, css, js, png, jpg, gif, svg, ico, pdf, xlsx]
    try_files: [index.html, .html, .htm, .txt, .xml, .json]
```

### Maintenance Page Not Showing

1. Verify maintenance mode is enabled:
```bash
grep "maintenance:" config/navigator.yml -A2
```

2. Check maintenance page exists:
```bash
ls -la public/503.html
```

3. Check Navigator logs for maintenance mode confirmation:
```
Maintenance mode enabled - static files will be served, dynamic requests will receive maintenance page
```

### Redirects Requiring Authentication Instead of Working

**Symptom**: `curl -I https://your-app.fly.dev/` returns `401 Unauthorized` instead of redirecting to `/showcase/studios/`

**Cause**: Authentication happens BEFORE redirects in the request flow. If the root path `/` requires authentication, Navigator never reaches the redirect handler.

**Solution**: Add auth pattern to exempt root path:
```yaml
auth:
  enabled: true
  auth_patterns:
    - pattern: "^/$"
      action: 'off'
```

Without this pattern, the request flow is:
1. `/` request arrives
2. Auth check blocks it (401 Unauthorized) ❌
3. Redirect never executes

With the pattern:
1. `/` request arrives
2. Auth check passes (exempted by pattern) ✅
3. Redirect executes → `/showcase/studios/`

## Summary

Navigator's maintenance mode provides an operational infrastructure environment:

**What continues:**
- ✅ Static file serving (pre-rendered pages, assets, documentation)
- ✅ Basic routing (redirects, rewrites)
- ✅ Remote service proxies (password, studios request)
- ✅ Authentication
- ✅ Health checks (synthetic 200 OK at `/up`)
- ✅ CGI scripts (configuration updates)

**What's disabled:**
- ❌ Dynamic application requests (show maintenance page)
- ❌ Action Cable WebSocket connections
- ❌ Managed processes (no Action Cable server, no Redis)
- ❌ Fly-Replay routes (no PDF/XLSX generation)

This design ensures fast startup during maintenance while keeping infrastructure operational. Users can access pre-rendered content, administrators can update configuration remotely, and monitoring systems stay healthy.
