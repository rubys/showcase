# Availability

Some students may have prior commitments that prevent them from either showing up before a certain time, or require them to leave early.

This feature is available for students when the _Heat Order_ setting is set to either _Random_ or _Availability_. You will also need to set a date for the event, specify a time between heats, and the start time of the first agenda item.

When these conditions are met, you will see an option to specify Availability when you add or edit a student. This can be entire event, before a certain time, or after a certain time.

## Heat Order Options

There are two approaches to handling availability constraints:

### Random Order <span>(best when there are few people with constraints)</span>
When _Heat Order_ is set to _Random_, the system schedules heats normally and then attempts to accommodate availability requests through a three-phase approach:

1. **Group exchanges** - Swaps entire heat groups to better time slots
2. **Individual rescues** - Moves single heats to available time windows
3. **Final cleanup** - Unschedules any remaining conflicts

### Availability-Based Order <span>(best when there are many people with constraints)</span>
When _Heat Order_ is set to _Availability_, the system proactively schedules heats based on participant constraints:

- **Early departures** (must leave by a certain time) are scheduled first
- **No constraints** are scheduled in the middle
- **Late arrivals** (can't arrive until a certain time) are scheduled last
- Within each category, heats are randomly ordered

This approach typically results in better accommodation of availability constraints with fewer unscheduled heats.

## Handling Unscheduled Heats

If a student's request can't be accommodated completely, some entries may be left as unscheduled and will show up as such on the Heats page. You can manually schedule these items by editing the heats and updating the heat number.