# Backups

Event databases, counter backgrounds, and solo music are all backed up.

There are two separate backups performed automatically:

  * Daily backups - these are stored on the same machine.
  * Idle backups - these are performed five minutes after the last access is made
    to the application.  These are stored in two places: on a separate machine at the
    same location, and on the [Hetzner backup host](./Hosting.md).

Additionally, I frequently make copies of the data onto my development machine
for testing.  I'm also starting to test deployment on [fly.io](https://fly.io/)
so there will eventually be more copies "in the cloud".

On the "publish" page there are links where you can export your database in
a number of formats.