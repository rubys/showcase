# Cloudflare integration

Current status:
  * Experiment is live at https://dance.showcase.party/regions/
  * https://smooth.fly.dev/showcase/ is still accessible, active, and primary

## Motivation

The ideal architecture for this application is one machine per studio using this application, where that
machine is close to the studio, and starts and stops on demand.  This makes memory usage very predictable,
isolates problems, and minimizes the affect of noisy neighbor problems.  More background can be found at
[Fly.io Blueprint: Shared Nothing Architecture](https://fly.io/docs/blueprints/shared-nothing/).

Currently this application is configured with an approximation: multiple geographically co-located studios
are served by a single always on machine.  This simplifies routing.

Solving the general problem requires a programmable router, and [Cloudflare Workers](https://workers.cloudflare.com/) addresses that need.  Benefits:
  * Having the worker insert [Fly-Prefer-Region](https://fly.io/docs/networking/dynamic-request-routing/#the-fly-prefer-region-request-header) or [Fly-Force-Instance-Id](https://fly.io/docs/networking/dynamic-request-routing/#the-fly-force-instance-id-request-header) headers based on the URL path,
  the Fly.io proxy can reliably direct requests to the correct machine without the application needing
  to worry about [Fly-Replay](https://fly.io/docs/networking/dynamic-request-routing/#the-fly-replay-response-header) or reverse proxying.
  * Serving up static assets and pre-rendered pages out of [R2 storage](https://developers.cloudflare.com/r2/) navigation to your event can avoid waking up machines.  Cloudflare can also serve the challenge response of HTTP authentication or login form for session based logins, meaning that only authenticated
  accesses are served by machines.
  * Routing requests based on URL path opens up the possibility of a mixed or hybrid cloud where some requests are served by one cloud provider and others by a different cloud provider.

## Implementation

The generated worker can be found at [https://dance.showcase.party/showcase.js](https://dance.showcase.party/showcase.js).  This currently fits comforably within Cloudflare's 1MB limit for workers, but eventualy
could need to be backed by a KV store or R2.

[prerender.rake](../../../lib/tasks/prerender.rake) and
[cloudflare.rake](../../../lib/tasks/cloudflare.rake) contains Rake tasks:
  * `prerender` generates the static site pages, using a technique _borrowed_ from [Sitepress](https://github.com/sitepress/sitepress).
  * `cloudflare:release` syncs the static site pages, assets, and images with Cloudflare R2.  Assets
  are kept for a minimum of three days enabling site visitors seemless access during and after a
  new deploy of a site.  This step can be run as a [deploy release_command](https://fly.io/docs/reference/configuration/#run-one-off-commands-before-releasing-a-deployment).
  * `cloudflare:deploy` does all of the above as well as generates and deploys a new worker.  This
  would be run the configuration changes (such as when a new studio is added).

## Costs

Cloudflare is a competitively priced DNS registrar, and both the worker and R2 usage appear to be covered by their free tier.

## TODOs

* Performance testing.  Initial experience has been positive so I haven't pursued it yet.
* Removal of now redundant `/showcase` as a part of the path.
* Dealing with demos: this would be the one unauthenticated access to my site.  
* Moving from region based routing to machine instance based routing.