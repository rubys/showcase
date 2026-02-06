# Ballrooms

Some of the bigger events partition the ballroom floor with stanchions and ropes for all or part of the agenda. The application supports splitting the floor into up to four separate ballrooms.

## Settings

Event-wide ballroom settings can be configured from the [Settings](./Settings) page:

- **One ballroom** - No splitting, all heats in the same area
- **Two ballrooms (split by role)** - Ballroom A for amateur followers with instructor, Ballroom B for amateur leaders (includes amateur couples)
- **Two ballrooms (rotating)** - Participants are evenly divided and rotate to a different ballroom for each group of dances, ensuring exposure to different judges
- **Three ballrooms (rotating)** - Same as above, across three ballrooms
- **Four ballrooms (rotating)** - Same as above, across four ballrooms

These settings can be overridden on an agenda item by item basis.

## Rotating Assignment

When using the rotating ballroom options (2, 3, or 4 ballrooms), the system:

1. **Tracks participants** - Each person is assigned to a ballroom and stays there within a group of dances
2. **Detects groups** - A new group starts each time the dances cycle back to the beginning of a style (e.g., when Smooth dances start over with Waltz again)
3. **Rotates across groups** - Participants are assigned to different ballrooms in subsequent groups, ensuring exposure to different judges
4. **Handles partner changes** - When partners have conflicting ballroom assignments, the system prefers keeping students stationary over professionals

### Overrides

The following overrides take precedence over the rotating assignment:

- **Heat-level ballroom** - Specific heats can be assigned to a particular ballroom
- **Studio preference** - Studios can have a preferred ballroom set in their settings

## Display

The ballroom (A, B, C, or D) appears on:

- Heat lists
- Mobile pages
- Judge's scoring pages
- Emcee pages

When adding [walk-on participants](./Scratches-and-Walk-ons) after the agenda is locked, you can select the ballroom for new participants.
