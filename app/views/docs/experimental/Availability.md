# Availability

Some students may have prior commitments that prevent them from either showing up before a certain time, or require them to leave early.

At the moment, this feature is only available for students, and only if
the _Heat Order_ setting is set to _Random_.  You will also need to set
a date for the event, specify a time between heats, and the start time of the first agenda item.

When these conditions are met, you will see
an option to specify Availability when you add or edit a student.  This can be entire event, before a certain time, or after a certain time.

Redo will attempt to accommodate these requests.  It does so by scheduling
as it normally would, and then looking for entire heats that it can swap to
accommodate requests.  The current algorithm is pretty simplistic and if you have a large number of students with availability restrictions, this approach may not be sufficient.

If a student's request can't be accommodated completely, some entries may be left as unscheduled, and will show up as such on the Heats page.  You
can manually schedule these items by editing the heats and updating the
heat number.