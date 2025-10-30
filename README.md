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
[CRUD](https://en.wikipedia.org/wiki/Create,_read,_update_and_delete) Rails 8.0.2
application using import maps for JavaScript and
[TailwindCSS](https://tailwindcss.com/) for CSS. The application uses Rails 8.0
configuration defaults and has been fully migrated to be compatible with SQL
reserved word quoting requirements. 

Models are split into two categories:

**Base models** support ballroom dance event management:
- Core competition: Event (singleton config), Person (all participants, STI disabled),
  Studio (with pairs), Dance (with scrutineering), Category (with extensions),
  Age, Level
- Heat & performance: Heat (numbered sessions), Entry (connects lead/follow/instructor),
  Solo (routines with optional formations), Formation (individual participants),
  Multi, MultiLevel
- **Heats are numbered** - all Heat records with the same number are on the floor
  simultaneously. Heats with `number >= 1` are scheduled; `number < 0` indicates
  scratched (withdrawn) heats that can be restored or permanently deleted
- **Split dances** - when a dance appears in multiple categories, there are multiple
  Dance records with the same name: one with positive order (canonical), others with
  `order < 0` that sync properties from the canonical dance
- Judging & scoring: Judge, Score (live updates via ActionCable), Recording
- Financial: Billable (packages/options, STI disabled), PackageInclude, PersonOption,
  Payment
- Seating: Table (grid positioning), StudioPair
- Music & questionnaires: Song, Question, Answer, Feedback

**Admin models** support system administration and multi-tenancy: Locale (service class),
Location, Showcase, User, Region, ApplicationRecord (base class with Tigris storage
integration).

The heat scheduler in
[app/controllers/concerns/heat_scheduler.rb](./app/controllers/concerns/heat_scheduler.rb)
uses a two-pass algorithm: first minimizing heat count, then balancing heat 
sizes. It interleaves different dance types within agenda categories and 
appends manually-ordered solos.

The table assignment system in
[app/controllers/concerns/table_assigner.rb](./app/controllers/concerns/table_assigner.rb)
and [app/controllers/tables_controller.rb](./app/controllers/tables_controller.rb)
offers two algorithms: **Regular Assignment** prioritizes keeping studios
together, while **Pack Assignment** maximizes table utilization. Both use a
two-phase algorithm (Phase 1 groups people into tables, Phase 2 places tables
on grid) and achieve 100% success rate for large studios (>10 people) and studio
pairs. Key features include:
- Event Staff isolation (studio_id = 0 never mixed with other studios)
- Studio Pair Handling (paired studios share tables or are placed adjacent)
- Optimal table utilization (fits small studios into existing tables first)
- Global position reservation with priority system (0-3)
- Contiguous block placement for large studios
- Smart consolidation to minimize total table count
- Sequential numbering following physical grid layout (row-major order)
- Drag-and-drop grid interface for manual arrangement
- Handles option tables via person_options join table

The initial configuration had a 8 year old i3
Linux box running Apache httpd handing SSL and reverse proxying the application
to a 2021 vintage Mac Mini M1 running the nginx configuration described above.
This approach could easily scale to be able to handle hundreds of events even
with a half dozen or so running concurrently, but had a hard dependency on
my house having both power and internet connectivity.  As such a different
architecture was needed.  See [ARCHITECTURE.md](./ARCHITECTURE.md) for
more details.
