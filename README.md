# Showcase

In between updates to [Agile Web Development with Rails
7](https://pragprog.com/titles/rails7/agile-web-development-with-rails-7/), I
keep my Rails skills sharp by developing small applications.

I also take ballroom dance lessons with my wife, and we have competed
internationally and at smaller local competitions.  For larger events there is commercial
software for scheduling "heats" where dancers go on the floor and be judged.
Smaller competitions use spreadsheets to track this.

Scheduling is deceptively hard, particularly if you have last minute changes
such as an instructor not being able to make the competition for any reason.
Manually making last minute changes can lead to scheduling mishaps, such as
having the same person being scheduled twice with different partners for the
same heat.

This application manages showcase events, from data entry to scheduling, to
generating of printed reports.  It can also be accessed by participants
on the day of the event to see the list of heats, and by judges to enter
scores.

# Getting up and running - bare metal, one event

Prerequisites:
[git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git) and
[ruby](https://www.ruby-lang.org/en/documentation/installation/).

```
git clone https://github.com/rubys/showcase.git
cd Showcase
bundle install
bin/rails db:prepare
bin/rails test
bin/rails test:system
bin/dev
```

Visit http://localhost:3000/ to see the event.

# Getting up and running - docker image, multiple events

Prerequisites:
[git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git),
[ruby](https://www.ruby-lang.org/en/documentation/installation/), and
[docker](https://docs.docker.com/get-docker/).

```
git clone https://github.com/rubys/showcase.git
cd Showcase
bundle install
rm config/credentials.yml.enc
bin/rails credentials:edit
$EDITOR config/tenant/showcases.yml
docker compose build
docker compose up
docker compose exec web bin/bootstrap
```

Visit http://localhost:9999/showcase/ to see the list of events.

# Implementation overview

This is pretty much a standard
[CRUD](https://en.wikipedia.org/wiki/Create,_read,_update_and_delete) Rails 7
application using import maps for JavaScript and
[TailwindCSS](https://tailwindcss.com/) for CSS. 

Models are provided for people (judges, emcees, instructors, students, and
guests), packages, options, ages, levels, studios, dances, categories, events,
heats, solos, formations, multi-heats, and scores, as well as a special
singleton table for event information and settings.

The heat scheduler can be found in
[app/controllers/concerns/heat_scheduler.rb](./app/controllers/concerns/heat_scheduler.rb).
It collects heats by agenda category, schedules them in two passes (first pass
minimizes the number of heats, the second pass balances heats size), interleaves
dances of different types within an agenda category, then appends solos.

Order of solos within an agenda category is controlled entirely manually via
drag and drop.

# Deployment (multi-tenancy)

The code base supports only a single event.

There are a number of blog posts out there on how to do
[multi-tenancy](https://blog.arkency.com/comparison-of-approaches-to-multitenancy-in-rails-apps/)
with Rails.  Phusion Passenger provides a [different
approach](https://stackoverflow.com/questions/48669947/multitenancy-passenger-rails-multiple-apps-different-versions-same-domain).

For this use case, the Phusion Passenger approach is the best match.  The
database for a mid-size local event is about a megabyte in size (about the size
of a single camera image), and can be kept in sqlite3.  Passenger provides a
[passenger_min_instances](https://www.phusionpassenger.com/library/config/nginx/reference/#passenger_min_instances)
`0` option that allow a reasonable number of past, present, and future events
to be hosted essentially without any overhead when not in use.  This does mean
that you have to accept the cold start times of the first access, but that
appears to be on the order of a second on modern hardware, which is acceptable.

The way this works is to set environment variables for each instance to control
the name of the database, the log file, base url, and pidfile.

For Action Cable, nginx is [preferred over Apache
httpd](https://www.phusionpassenger.com/library/config/apache/action_cable_integration/).
The [documentation for Deploying multiple apps on a single server
(multitenancy)](https://www.phusionpassenger.com/library/deploy/nginx/) is
still listed as todo, but the following is what I have been able to figure out:

- One action cable process is allocated per server (i.e., listen port).
- In order to share the action cable process, all apps on the same server will
  need to share the same redis URL and channel prefix.  The [Rails
  documentation](https://guides.rubyonrails.org/action_cable_overview.html#redis-adapter)
  suggests that you use a different channel prefix for different applications
  on the same server -- **IGNORE THAT**.
- Instead, use environment variables to stream from, and broadcast to, different
  action cable channels.

The end result is what outwardly appears to be a single Rails app, with a
single set of assets and a single cable.  One additional rails instance
serves the index and provides a global administration interface.

# Topology

The initial configuration had a 8 year old i3
Linux box running Apache httpd handing SSL and reverse proxying the application
to a 2021 vintage Mac Mini M1 running the nginx configuration described above.
This approach could easily scale to be able to handle hundreds of events even
with a half dozen or so running concurrently, but had a hard dependency on
my house having both power and internet connectivity.

An architecture of a single nginx process per group of rails apps, one per
event, is well suited to deployment in a Docker container to one of any number
of available cloud providers.  Doing so not only provides scalability and
privacy, it eliminates any concerns of the app not being available due to
power or network outages.

The current configuration is hosted on [Fly.io](https://fly.io).  It consists
of one machine per region, with each machine hosting multiple locations, and each
location hosting one or more events.  A 
[stimulus controller and turbo hook](https://github.com/rubys/showcase/commit/84a1e20749cd189254f35896779a9f5439d3c939) adds a [`Fly-Prefer-Region`](https://fly.io/docs/networking/dynamic-request-routing/#the-fly-prefer-region-request-header) header to requests, and nginx is
configured to respond with a [`Fly-Replay`](https://fly.io/docs/networking/dynamic-request-routing/#the-fly-replay-response-header) header and/or
reverse proxy requests to the [proper region](https://fly.io/docs/networking/private-networking/#fly-io-internal-addresses).

A separate [printing app](https://fly.io/blog/print-on-demand/) handles
generation of PDFs, and a separate
[logging app](https://fly.io/blog/redundant-logs/) provides access to logs.

# Backups

A typical database is approximately a megabyte so it doesn't make sense
to optimize for storage.  To the contrary, each database is replicated
to every region as well as to two separate off-size locations.  Replications
are implemented using rsync, and occur when the passenger application in a
given region has been idle for five minutes.

A cron job in my home server takes daily backups, and uses hard links
to optimize for the case where the database hasn't changed in on that day.
As these backups are stored on a terabyte SSD, a growth rate of a few
megabytes per day is not a concern.

# Performance

* While there are a few outliers (e.g., agenda redo, pdf generation), most
  requests are satisfied in approximately 100ms.
* Peak load rates approach 1 request per second per event.
* Typical usage profile
  * days (or even weeks) of data entry, often by a single person,
    other times by a group of people in the same geographic region.
  * a day or so of final tweaks and generation of PDFs
  * a day or two of a judge or a small number of judges entering scores.
    These judges will all be in the same physical locaion.
  * a small number of hours of PDF generation.

Given this profile, even a modest (shared-cpu-1x) VM has can support
multiple simultaneous events with ease, with plenty of room for
growth should it be needed.

Access to remote events is possible but not optimized for.  That being
said, casual browsing of events as far away as Sydney from the US is
very doable with resonable reponse times. 
