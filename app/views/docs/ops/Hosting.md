# Hosting

## [smooth.fly.dev](https://smooth.fly.dev/)

Starting with a number of events in late 2023, and for all events in 2024 and beyond,
this software is hosted on [fly.io](https://fly.io/) which
enables me to deploy on servers around the word.  Events are hosted
automatically be hosted at the nearest site.  Deployment to a
new [region](https://fly.io/docs/reference/regions/) can be done in
a matter of minutes.

---

## [rubix.intertwingly.net](https://rubix.intertwingly.net/smooth/)

Prior to this point, the application was hosted on a Mac Mini in the attic of
my house outside of Raleigh, North Carolina.  Capacity was never an issue,
but concerns that power and network failures would temporarily prevent access at times
lead me to seek an alternative.

Important things to understand:

   * This is running the exact same software
   * Five minutes after the last time anybody visits a page or made an update on any machine, all databases will be backed up and uploaded to all other machines, so the data everywhere is kept up to date.

What this means is: **don't switch machines unless there is a problem, and one you switch don't switch back until you have verified that the database has your latest updates, otherwise you can lose data.**

---

## [hetzner.intertwingly.net](https://hetzner.intertwingly.net/showcase/)

I also have a [hot backup](https://hetzner.intertwingly.net/showcase/)
running on [Hetzner](https://www.hetzner.com/) in [Ashburn, VA](https://www.hetzner.com/news/11-21-usa-cloud/).  This machine will receive updates from all other machines, but updates made on this machine won't be synchronized back.

---

## Self hosting

I've provided [installation instructions](https://github.com/rubys/showcase#getting-up-and-running---bare-metal-one-event)
for those that wish to run this themselves.  If you have a machine that is capable of running a spreadsheet and
a web browser you can run this yourself, but security, backups, and network access will be items you will need
to address.

Understandably, most will opt to use my host (and in the future hosts).  Just be aware that
for security reasons I don't currently allow users to do the following:

  * Allocate new events
  * Set/reset passwords
  * Change who can access individual events

For these actions, contact me via email, text, or facebook.
