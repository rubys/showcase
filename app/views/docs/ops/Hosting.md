# Hosting

This application is currently hosted on a Mac Mini in the attic of
my house outside of Raleigh, North Carolina.  Capacity is not an issue,
but power and network failures may temporarily prevent access at times.

For that reason, I have a [hot backup](https://hetzner.intertwingly.net/showcase/)
running on [Hetzner](https://www.hetzner.com/) in [Ashburn, VA](https://www.hetzner.com/news/11-21-usa-cloud/).  Important things to understand:

   * This is running the exact same software
   * Five minutes after the last time you visit a page or made an update your entire event database will be uploaded to this machine, so the data there is kept up to date.  This will occur continuously until and unless you make an update on the Hertner machine, and will resume once you make an update on my Mac Mini.

What this means is: **don't use the Hetzner machine unless there is a problem, and one you switch don't switch back unti I can resynchonize the databases, otherwise you can lose data.**

To use the Hetzer machine, go to the [hetzner showcase](https://hetzner.intertwingly.net/showcase/), and find your event.

---

I'm also testing deployment on [fly.io](https://fly.io/) which will
allow me to deploy on servers around the word.  The new site will be
[smooth.fly.dev](https://smooth.fly.dev/), and is currently deployed
at the following sites: ATL, DFW, IAD, MIA, and ORD.  Events will
automatically be hosted at the nearest site.  Deployment to a
new [region](https://fly.io/docs/reference/regions/) can be done in
a matter of minutes.

---

I've provided [installation instructions](https://github.com/rubys/showcase#getting-up-and-running---bare-metal-one-event)
for those that wish to run this themselves.  If you have a machine that is capable of running a spreadsheet and
a web browser you can run this yourself, but security, backups, and network access will be items you will need
to address.
