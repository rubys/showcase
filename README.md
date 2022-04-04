# Showcase

In between updates to [Agile Web Development with Rails
7](https://pragprog.com/titles/rails7/agile-web-development-with-rails-7/), I
keep my Rails skills shap by developing small applications.

I also take ballroom dance lessons with my wife, and we have competed
nationally and at smaller local competitions.  Nationally, there is commercial
software for scheduling "heats" where dancers go on the floor and be judged.
Smaller competitions use spreadsheets to track this.

Scheduling is deceptively hard, particularly if you have last minute changes
such as an instructor not being able to make the competition for any reason.
Manually making last minute changes can lead to scheduling mishaps, such as
having the same person being scheduled twice with different partners for the
same heat.

This is application that does exactly that, from data entry to scheduling, to
generating of printed reports.

# Getting up and running

Prerequisites:
[git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git) and
[ruby](https://www.ruby-lang.org/en/documentation/installation/).

```
git clone -b main
cd Showcase
bundle install
bin/rails db:create db:migrate db:seed
bin/rails test
bin/rails test:system
bin/dev
```

# Implementation overview

This is pretty much a standard
[CRUD](https://en.wikipedia.org/wiki/Create,_read,_update_and_delete) Rails 7
application using import maps for JavaScript and
[TailwindCSS](https://tailwindcss.com/) for CSS. 

Models are provided for people (judges, emcees, instructors, students, and
guests), ages, levels, studios, dances, categories, events, heats, solos, and
scores, as well as a special table for event information and settings.

The heat scheduler can be found in
[app/controllers/concerns/heat_scheduler.rb](./app/controllers/concerns/heat_scheduler.rb).
It collects heats by agenda category, schedules them in two passes (first pass
minimizes the number of heats, the second pass balances heats size), interleves
dances of different types within an agenda category, then appends solos.

Order of solos within an agenda category is controlled entirely manually via
drag and drop.

# Deployment (multi-tenancy)

The current code base supports only a single event.

There are a number of blog posts out there on how to do
[multi-tenancy](https://blog.arkency.com/comparison-of-approaches-to-multitenancy-in-rails-apps/)
with Rails.  Phusion Passenger provides a [different
approach](https://stackoverflow.com/questions/48669947/multitenancy-passenger-rails-multiple-apps-different-versions-same-domain).

For this use case, the Phusion Passenger is the best match.  The database for a
mid-size local event is about a megabyte in size (about the size of a single
camera image), and can be kept in sqlite3.  Passenger provides a
[passenger_min_instances](https://www.phusionpassenger.com/library/config/nginx/reference/#passenger_min_instances)
`0` option that allow a reasonable number of past, present, and future events
to be hosted esentially without any overhead.  It does mean that you have to
accept the cold start times of the first access, but that appears to be on the
order of a second on modern hardware, which is acceptable.

The way this works is to set environment varialbes for each instance to control
the name of the database, the log file, base url, and pidfile.

For Action Cable, nginx is preferred over Apache.  The [documentation for
this](https://www.phusionpassenger.com/library/deploy/nginx/) is still listed
as todo, but the following is what I have been able to figure out:

- One action cable process is allocated per server (i.e., listen port).
- In order to share the action cable process, all apps on the same server will
  need to share the same redis URL and channel prefix.  The (Rails
documentation)[https://guides.rubyonrails.org/action_cable_overview.html#redis-adapter]
suggests that you use a different channel prefix for different applications on
the same server -- **IGNORE THAT**.
- Instead, use environment varialbes to stream from and broadcast to different
  action cable channels.

The end result is what outwardly appears to be a single Rails app, with a
single set of assets and a single cable.  One additional rails instance to
serve the index and ultimately provide global administration and features
completes the picture.

# Topology

The initial (and as of this writing, current) configuration has a 8 year old
Linux box running Apache httpd handing SSL and reverse proxying the application
to a 2021 vintage Mac Mini M1 running the nginx configuration described above.
This appraoch should easily scale to be able to handle hundreds of events even
with a half dozen or so running concurrently.

An architecture of a single nginx process per group of rails apps, one per
event is well suited to deployment in a Docker container to one of any number
of available cloud providers.  Doing so would not only give scalability and
privacy, it would eliminate any concerns of the app not being available due to
power or network outages.

# Futures (planned features)

Some of features being explored:

- Cloud deploymen (described above)
- User access control and authentication
    - Likely initially basic auth within the application
    - OAuth with providers like google, facebook, etc is indeed possible
- Basic "bulletin board" feature both for support request and for studios to
  coordinate plans
