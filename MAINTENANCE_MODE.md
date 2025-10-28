# Maintenance Mode Guide

This document explains how maintenance mode works in the Navigator-managed showcase application.

## Overview

Maintenance mode allows you to perform application updates, database migrations, or other maintenance tasks while keeping infrastructure and static content accessible.

## What Continues Working During Maintenance

When maintenance mode is enabled (`maintenance.enabled: true`), the following continue to function normally:

### Infrastructure Components

1. **Health Checks** (`/up`)
   - Load balancers and monitoring systems continue working
   - Ensures container orchestration doesn't terminate instances

2. **Authentication**
   - htpasswd authentication remains active
   - Public paths configured in `auth.public_paths` remain accessible
   - Protected resources still require credentials

3. **Static Files**
   - All files matching `allowed_extensions` are served directly
   - Extensions: `html, htm, txt, xml, json, css, js, png, jpg, gif, svg, ico, pdf, xlsx`
   - Includes pre-rendered studio pages, documentation, and assets

4. **Try Files**
   - Extensionless URLs resolved with try_files extensions
   - Examples: `/studios/raleigh` → `/studios/raleigh.html`
   - Configured extensions: `index.html, .html, .htm, .txt, .xml, .json`

### Routing & Proxying

5. **Redirects**
   - All configured redirects continue working
   - Example: `/` → `/showcase/studios/`
   - Users get consistent navigation experience

6. **URL Rewrites**
   - Asset path normalization continues
   - Example: `/assets/*` → `/showcase/assets/*`
   - Ensures static assets load correctly

7. **Fly-Replay Routes**
   - PDF generation routed to `smooth-pdf` app
   - XLSX generation routed to `smooth-pdf` app
   - Cross-region routing to other Fly.io regions
   - Document generation remains available

8. **CGI Scripts**
   - Configuration update endpoint (`/showcase/update_config`)
   - Allows remote configuration updates during maintenance
   - Can reload configuration without container restart

9. **Reverse Proxies**
   - Action Cable WebSocket connections to standalone server
   - Password management proxy to rubix
   - Studio request proxy to rubix
   - Standalone services remain operational

## What Shows Maintenance Page

**Only**: Dynamic requests to Rails tenant applications

When a request reaches the web application proxy phase (after all static/infrastructure handlers), users see the configured maintenance page (`public/503.html`).

### Example Scenarios

✅ **Available during maintenance:**
- `/showcase/studios/` - Pre-rendered studio index (static HTML)
- `/showcase/studios/raleigh.html` - Pre-rendered studio page
- `/showcase/assets/application.css` - Static assets
- `/showcase/docs/` - Static documentation
- `/showcase/2025/boston/invoice.pdf` - PDF generation (via Fly-Replay)
- `/showcase/update_config` - CGI configuration endpoint
- `/up` - Health check

❌ **Shows maintenance page:**
- `/showcase/2025/boston/` - Dynamic Rails tenant request
- `/showcase/2025/boston/heats` - Dynamic Rails tenant request
- `/showcase/2025/boston/scores` - Dynamic Rails tenant request

## Configuration Requirements

**IMPORTANT**: The maintenance configuration file (`config/navigator-maintenance.yml`) must include all infrastructure components to ensure they continue working during maintenance mode:

### Required Sections

1. **server.root_path** - URL path prefix (e.g., `/showcase`)
2. **server.static** - Static file configuration with `allowed_extensions` and `try_files`
3. **routes** - Redirects, rewrites, and reverse proxies
4. **managed_processes** - Standalone services like Action Cable
5. **auth** - Authentication configuration with public paths
6. **maintenance.enabled: true** - Enable maintenance mode

Without these sections in the maintenance config, the corresponding features won't work during the maintenance window.

### Infrastructure Components to Include

```yaml
# Example: Key infrastructure sections needed
routes:
  redirects:
    - from: "^/(showcase)?$"
      to: /showcase/studios/
  rewrites:
    - from: "^/assets/(.*)"
      to: /showcase/assets/$1
  reverse_proxies:
    - path: "^/showcase(/cable)$"
      target: http://localhost:28080$1
      websocket: true

managed_processes:
  - name: action-cable
    command: bundle
    args: [exec, puma, "-p", "28080", cable/config.ru]

auth:
  enabled: true
  public_paths:
    - /showcase/assets/
    - /showcase/studios/
  auth_patterns:
    # CRITICAL: Allow root path so redirects work
    - pattern: "^/$"
      action: 'off'
```

**IMPORTANT**: The `auth_patterns` must include an exemption for the root path (`^/$`) to allow redirects to work. Without this, authentication blocks the request before it reaches the redirect handler, and users see a 401 Unauthorized instead of being redirected.

See `config/navigator-maintenance.yml` for the complete example configuration.

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

Health checks continue working, so monitoring systems won't alert:
- `/up` returns 200 OK during maintenance
- Containers stay healthy
- Load balancers continue routing

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

### CGI Endpoint Not Working

CGI scripts continue during maintenance, but check:
1. Path matches configuration: `/showcase/update_config`
2. Method is POST (not GET)
3. Script has execute permissions

## Summary

Navigator's maintenance mode provides the optimal balance:
- ✅ Infrastructure remains operational
- ✅ Static content accessible
- ✅ Routing and proxying continue
- ❌ Only dynamic app requests blocked

This design ensures the best user experience during maintenance periods while protecting the application during updates.
