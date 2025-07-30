# Showcase

In between updates to [Agile Web Development with Rails
8](https://pragprog.com/titles/rails8/agile-web-development-with-rails-8/), I
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
[CRUD](https://en.wikipedia.org/wiki/Create,_read,_update_and_delete) Rails 8
application using import maps for JavaScript and
[TailwindCSS](https://tailwindcss.com/) for CSS. 

Models are split into two categories:

**Base models** support ballroom dance event management: ages (with costs), 
billables (packages and options), categories (with extensions), dances, entries, 
events, feedbacks, formations, heats, judges, levels, multi-dances, package 
includes, people (students, instructors, guests, etc.), person options, 
recordings, scores, solos, songs, studios (with studio pairs), and tables.

**Admin models** support system administration and multi-tenancy: locales, 
locations, regions, showcases, and users.

The heat scheduler in
[app/controllers/concerns/heat_scheduler.rb](./app/controllers/concerns/heat_scheduler.rb)
uses a two-pass algorithm: first minimizing heat count, then balancing heat 
sizes. It interleaves different dance types within agenda categories and 
appends manually-ordered solos.

The table assignment system in
[app/controllers/concerns/table_assigner.rb](./app/controllers/concerns/table_assigner.rb)
offers two algorithms: **Regular Assignment** prioritizes keeping studios 
together, while **Pack Assignment** maximizes table utilization. Both support 
locked tables for special requirements and achieve near 100% success rate 
using intelligent grid placement for complex seating scenarios.

The initial configuration had a 8 year old i3
Linux box running Apache httpd handing SSL and reverse proxying the application
to a 2021 vintage Mac Mini M1 running the nginx configuration described above.
This approach could easily scale to be able to handle hundreds of events even
with a half dozen or so running concurrently, but had a hard dependency on
my house having both power and internet connectivity.  As such a different
architecture was needed.  See [ARCHITECTURE.md](./ARCHITECTURE.md) for
more details.
