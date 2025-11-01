Showcase competitions happen live at single locations with small, focused user groups—typically a few judges entering scores during an event. Each event is completely independent: separate database, separate Rails instance, no shared state. This [shared-nothing](https://en.wikipedia.org/wiki/Shared-nothing_architecture) pattern eliminates contention and allows horizontal scaling by simply adding machines.

The Showcase application has evolved over several years of production use to support 75+ dance studios across 350+ events in 8 countries on 4 continents. This document describes the current architecture and some possibilities for future improvements. The architecture leverages [Fly.io](https://fly.io/) for global distribution and [Navigator](https://github.com/rubys/showcase/tree/main/navigator) (a custom Go reverse proxy) for multi-tenancy and intelligent routing.

## Architecture overview

The system consists of four independent but coordinated components:

### 1. Showcase (the Rails application)

A typical Rails 8.0 application managing a single event—completely unaware of other tenants or deployment topology. Each instance runs with:
- Its own SQLite database (e.g., `2025-boston.sqlite3`)
- Environment variables defining database location and scope (`RAILS_APP_DB`, `RAILS_APP_SCOPE`)
- Standard Rails models split into **base models** (Event, Person, Studio, Dance, Heat, Entry, etc.) and **admin models** (Location, Showcase, User, Region)

Running `bin/dev db/2025-boston.sqlite3` starts a single-tenant instance. The application itself knows nothing about multi-tenancy.

### 2. Administration (the index application)

A smaller Rails application sharing the same codebase but running with a different database (`index.sqlite3`). It provides:
- Event and region management UI
- User authentication and authorization
- Studio request forms
- The [Configurator](https://github.com/rubys/showcase/blob/main/app/controllers/concerns/configurator.rb) concern that generates Navigator configuration

Routes for administration (like `/studios/:location/request`) are only active when `RAILS_APP_DB=index`. Running `bin/dev index` starts the index application.

### 3. Navigator (the reverse proxy)

An independent Go-based server that knows nothing about Rails. It:
- Reads `config/navigator.yml` for routing and tenant definitions
- Starts Rails processes on-demand with appropriate environment variables
- Routes requests based on URL paths to the correct tenant
- Serves static assets directly without Rails
- Executes lifecycle hooks at key events
- Manages machine idle/suspend behavior

Navigator runs as a separate process and communicates with Rails only via HTTP.

### 4. Scripts and configuration

Glue code that connects the index database to Navigator:
- [Config update job](https://github.com/rubys/showcase/blob/main/app/jobs/config_update_job.rb) coordinates updates across machines and provides progress updates
- [update_configuration.rb](https://github.com/rubys/showcase/blob/main/script/update_configuration.rb) CGI script triggered by HTTP POST
- [RegionConfiguration](https://github.com/rubys/showcase/blob/main/lib/region_configuration.rb) library generates YAML files
- [Configurator concern](https://github.com/rubys/showcase/blob/main/app/controllers/concerns/configurator.rb) reads from index database and generates `navigator.yml`
- [ready.sh](https://github.com/rubys/showcase/blob/main/script/ready.sh) Navigator hook that runs after config reloads

When an admin creates a new event, the index database is updated, scripts regenerate `navigator.yml`, and Navigator reloads—all without redeploying the application.

## Deployment model

### Running everything on one machine

Each Fly.io machine is a complete VM, not just a container, so all services for an event run together: Rails, SQLite, Redis, Navigator, Action Cable, and supporting scripts. This keeps latency low and reliability high by eliminating network calls.

Current resource usage per machine:
- **CPU**: 2 shared vCPUs (modest, primarily for quick deployments)
- **Memory**: 2GB (handles peak loads during live events)
- **Storage**: 1GB volume with auto-extension

Multiple processes run via [Procfile.fly](https://github.com/rubys/showcase/blob/main/Procfile.fly) started by the [docker-entrypoint](https://github.com/rubys/showcase/blob/main/bin/docker-entrypoint) script.

### Multi-tenancy with Navigator

Each machine hosts multiple events using [Navigator](https://rubys.github.io/navigator/), a Go-based reverse proxy that manages separate Rails instances for each tenant. Each event gets:

- Its own SQLite database (~1MB per event)
- Its own Rails process (spawned on-demand)
- Its own environment variables (configured via [navigator.yml](https://github.com/rubys/showcase/blob/main/config/navigator.yml))
- Shared Action Cable server and Redis instance

Navigator handles:
- **Process management**: Starts Rails instances on first request, terminates after 5 minutes of inactivity
- **Routing**: URL path-based routing to correct tenant (e.g., `/showcase/2025/boston/` → boston database)
- **WebSockets**: Routes `/cable` connections to shared Action Cable server
- **Static assets**: Serves files directly without Rails overhead
- **Authentication**: htpasswd-based auth with per-path exclusions
- **Health checks**: `/up` endpoint for monitoring

This approach allows one machine to efficiently serve dozens of past, present, and future events with minimal overhead when idle.

### Action Cable architecture

Following [Rails best practices](https://guides.rubyonrails.org/action_cable_overview.html#running-standalone-cable-servers), the application runs Action Cable servers as standalone servers. However, the multi-tenant architecture requires a specialized approach:

**One cable server per machine, shared between all tenants**. Using Fly-Replay and reverse proxy routing via Navigator, each machine runs a single Action Cable server that handles WebSocket connections for all events on that machine. This design has important implications:

1. **Stream naming**: Cable stream names must be either unique to the tenant (include event identifier) or unique to the request (include session/user identifier). This prevents cross-tenant data leakage.

2. **Limited database access**: The Action Cable server does not have access to tenant databases. It operates independently of the Rails tenant processes.

3. **Broadcast-only communication**: All data flows one direction: server to client. The cable server can broadcast:
   - Progress updates (file uploads, batch operations)
   - Data change notifications (triggering client-side reloads)
   - Specific real-time information (current heat number, live scores)

4. **Request/response via HTTP**: If a client needs to update the server, it uses standard HTTP requests. Updates are processed in two ways:
   - **Synchronous processing**: Happens within the controller action (immediate response)
   - **Asynchronous processing**: Happens in background jobs (with progress broadcasts via cable)

This architecture enables real-time updates during live events (judges entering scores, heat progression) while maintaining tenant isolation and keeping the cable server simple and stateless.

### Global distribution

Events are distributed across multiple regions (currently 8 Fly.io regions across US, Europe, Asia, and Australia). Each region runs an identical machine, all accessing the same Tigris storage.

Request routing happens at three levels:

1. **Client-side routing**: JavaScript [region_controller.js](https://github.com/rubys/showcase/blob/main/app/javascript/controllers/region_controller.js) adds `fly-prefer-region` headers to Turbo requests, leveraging [Turbo Drive](https://turbo.hotwired.dev/handbook/introduction#turbo-drive%3A-navigate-within-a-persistent-process) to intercept navigation.

2. **Navigator routing**: The [navigator.yml](https://github.com/rubys/showcase/blob/main/config/navigator.yml) configuration defines regional routing rules using Fly.io's internal networking for cross-region requests.

3. **Fly-Replay**: For requests >1MB (like audio file uploads), Navigator uses [reverse proxy](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/) to bypass the [1MB Fly-Replay limit](https://fly.io/docs/networking/dynamic-request-routing/#limitations).

This enables low-latency access for customers worldwide. Tigris provides globally distributed object storage with automatic replication.

### PDF generation appliance

PDF generation uses [puppeteer](https://pptr.dev/) and Chrome, which requires significantly more memory than the main app. These run on separate on-demand machines that spin up when needed and stop when idle.

Navigator configuration uses Fly-Replay to route PDF requests to the dedicated appliance:

```yaml
routes:
  fly:
    replay:
      - path: "^/showcase/.+\\.pdf$"
        target: "app=smooth-pdf"
```

This pattern can apply to any resource-intensive operations: video encoding, audio transcription, large batch processing, etc. See [Print on Demand](https://fly.io/blog/print-on-demand/) for details.

## Key architectural patterns

### Auto-scaling at multiple levels

The architecture implements auto-scaling at three levels to minimize compute costs:

1. **Machine-level**: Fly.io suspends machines after 30 minutes of inactivity (configured in Navigator). Suspended machines consume no compute or memory resources. Fly.io automatically resumes machines on incoming requests.

2. **Tenant-level**: Navigator starts Rails processes on-demand when requests arrive and stops them after 5 minutes of inactivity. This allows dozens of events to coexist on one machine with minimal resource usage.

3. **Appliance-level**: PDF generation machines spin up only when needed and stop when idle, keeping costs negligible despite having 5 machines available.

This multi-level approach means most of the 350+ events are idle most of the time, consuming zero compute resources until accessed. Storage costs (volumes and Tigris S3) remain constant regardless of activity level.

### Local-first data access

The architecture eliminates network latency through aggressive local-first design:

**Static assets** (CSS, JavaScript, images, HTML index pages) are stored on every machine and served directly by Navigator without requiring a Rails tenant. This means assets are always local to the requestor, even for remote events—no CDN needed.

**Databases** are stored on local volumes and only synced to Tigris when applications go idle:
- **Zero network latency** for database operations during active use
- **Databases download from Tigris** on first access after machine resume
- **Automatic backup to Tigris** when tenant Rails processes shut down after inactivity

Each database resides on only one machine, and dynamic requests are routed to the correct machine via Fly-Replay or reverse proxy. Even for remote requests, only the HTTP request and response travel the globe—all database access is local and managed by Rails's existing connection pooling. No additional database connection pooling layer is needed.

The only network-dependent operations are Active Storage accesses for uploaded files (songs, audio recordings). Even here, DJs can download complete playlists for offline use via the [OfflinePlaylistJob](https://github.com/rubys/showcase/blob/main/app/jobs/offline_playlist_job.rb), which packages all songs into a downloadable ZIP file.

## Operations

### Administration and provisioning

Event provisioning uses a live configuration update system that completes in ~30 seconds:

**When a user requests a new event** (via `/studios/:location/request`):
1. Form submission creates Showcase record in index database
2. Background job ([ConfigUpdateJob](https://github.com/rubys/showcase/blob/main/app/jobs/config_update_job.rb)) starts:
   - Syncs index.sqlite3 to Tigris (S3)
   - Discovers active Fly.io machines (skips suspended ones)
   - POSTs to `/showcase/update_config` on each machine using `Fly-Force-Instance-Id` header

**Each machine's CGI script** ([update_configuration.rb](https://github.com/rubys/showcase/blob/main/script/update_configuration.rb)) runs:
1. Fetches updated index.sqlite3 from Tigris
2. Regenerates htpasswd file (authentication)
3. Regenerates showcases.yml (event metadata)
4. Regenerates navigator.yml (tenant routing)

**Navigator detects config changes** and reloads via SIGHUP, triggering the ready hook ([ready.sh](https://github.com/rubys/showcase/blob/main/script/ready.sh)):
1. Regenerates pre-rendered static HTML pages
2. Downloads/updates event databases from Tigris
3. Continues serving requests while optimizations run in background

**Real-time progress**: User sees live updates via ActionCable as machines are updated, then automatically redirects to their new event.

The admin UI also provides:
- Event and region management
- Log viewer for all servers
- Sentry integration for error monitoring

This approach eliminates the need for `fly deploy` when adding events, reducing provisioning time from minutes to seconds.

### Zero-downtime deployments

Deployments must take machines offline to replace images and restart services. To minimize user impact:

1. **Navigator starts immediately** with a [maintenance page](https://showcase.party/503.html) that auto-refreshes every 5 seconds
2. **Startup scripts** run in parallel: database migrations (from Tigris), Navigator config generation
3. **Navigator reloads** via SIGHUP when ready, switching from maintenance mode to normal operation

Migration lists are compared directly without starting Rails, and the demo database is prepared at build time. Databases are accessed from Tigris on-demand. Result: typically ~2 second delay when Rails instances restart on first request after deployment.

### Maintenance mode

Navigator supports maintenance mode that keeps infrastructure operational while blocking dynamic application requests:

**What continues during maintenance:**
- Static file serving (pre-rendered pages, assets, documentation)
- Basic routing (redirects, rewrites)
- Remote service proxies
- Authentication (htpasswd with public paths)
- Synthetic health check at `/up` (no Rails required)
- CGI scripts including `/showcase/update_config` for remote configuration updates

**What's disabled:**
- Dynamic Rails tenant requests (show maintenance page)
- Action Cable WebSocket connections
- Managed processes (Action Cable server, Redis)
- Fly-Replay routes (PDF/XLSX generation)

The maintenance configuration (`config/navigator-maintenance.yml`) is automatically generated during Docker build from the same [Configurator](https://github.com/rubys/showcase/blob/main/app/controllers/concerns/configurator.rb) module that builds the full Navigator config, ensuring consistency. Shared builder methods (`build_server_config_base`, `build_static_config`, `build_public_paths`, `build_health_check_config`) eliminate duplication.

Critical pattern: Authentication patterns must exempt the root path (`^/$`) to allow redirects to execute before auth checks, preventing `401 Unauthorized` responses.

Maintenance mode enables zero-downtime updates by switching configuration via the ready hook or CGI endpoint without container restarts.

### Backups

Databases are small (~1MB each), stored in [Tigris](https://www.tigrisdata.com/) (S3-compatible object storage on Fly.io):

1. **Cloud storage**: All databases and uploaded files stored in Tigris, accessible from any region
2. **Volume auto-extension**: Fly.io volumes automatically grow when 80% full for local caching
3. **Off-site backups**: Home server (Mac mini) and [Hetzner](https://www.hetzner.com/) VPS maintain complete copies
4. **Daily snapshots**: Automated daily backups using hard links for unchanged files (years of history retained)

Having local copies makes reproducing bugs and testing fixes straightforward. The home server doubles as a staging environment.

### Logging

Multiple redundant logging systems ensure logs are available when needed (they've been used to reconstruct lost data from POST requests):

1. **Volume logs**: Rails broadcasts to local volume in addition to stdout
2. **Centralized logging**: Dedicated [logger app](https://github.com/rubys/showcase/tree/main/fly/applications/logger) stores logs on volumes (7 day retention) with a web UI for browsing
3. **Off-site archive**: All logs backed up to home server indefinitely
4. **Error monitoring**: [Sentry](https://sentry.io/) integration for real-time error tracking and alerts

See [Multiple Logs for Resiliency](https://fly.io/blog/redundant-logs/) for details.

## Operating costs

Current infrastructure (8 regions, 350+ events):

- **Compute**: 8 machines × 2 vCPU shared × 2GB RAM
- **Volumes**: 8 × 1GB with auto-extension
- **Appliances**: 5 on-demand PDF generation machines (minimal cost)
- **Logging**: 1 dedicated log server machine

Estimated monthly cost before Fly.io plan allowances: ~$60-80. Actual cost varies with usage patterns and current Fly.io pricing.

## Summary

Showcase demonstrates that shared-nothing architectures work well when data naturally partitions (one database per customer/event):

**Key patterns:**
- Co-locate services on single machines for simplicity and performance
- Use Navigator for multi-tenancy with on-demand Rails process management
- Auto-scale at multiple levels (machine, tenant, appliance) to minimize costs
- Store data locally with Tigris backup, eliminating network latency
- Route requests intelligently across regions while keeping data access local
- Offload resource-intensive operations to on-demand appliance machines
- Maintain multiple backup and logging systems with active monitoring
- Provide smooth deployments with maintenance pages and fast startup
- Automate administration via live configuration updates

Currently serving 75+ dance studios across 350+ events in 8 countries on 4 continents from 8 regions at modest cost.

## Possible improvements

This architecture works well but has room for enhancement:

1. **Multi-cloud federation**: The [Hetzner deployment](config/deploy.yml) demonstrates Kamal deployment to non-Fly.io providers. The showcase.party domain uses Cloudflare's anycast network, which could route requests via Cloudflare Workers to machines across multiple cloud providers (Fly.io, Hetzner, AWS, etc.) based on DNS names. This would provide vendor independence and geographic optimization.

2. **Metrics and observability**: Add Prometheus/OpenTelemetry integration to better understand usage patterns and optimize resource allocation

3. **Progressive Web App**: Enable offline capabilities for judges to enter scores without reliable connectivity during events

The current architecture prioritizes simplicity and reliability over optimization, which has proven effective for the workload. Future improvements should maintain these priorities while addressing specific pain points as they emerge.
