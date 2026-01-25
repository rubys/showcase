# Ballroom Assignment Enhancement Plan

**Status: IMPLEMENTED** (2026-01-24)

## Overview

Extend ballroom assignment to support 3-4 physical ballrooms while minimizing participant travel and ensuring exposure to different judges across blocks of dances.

## Background

Currently, `assign_rooms` in `app/controllers/concerns/printable.rb` handles ballroom assignment per-heat-number in a stateless manner. The existing options are:

1. One ballroom
2. Two ballrooms split by role (A: amateur follower + instructor, B: amateur leader)
3. Evenly split couples between ballrooms
4. Assign ballrooms by studio

Options 3 and 4 have overlapping behavior and will be merged.

## New Options

| Setting Value | Description |
|---------------|-------------|
| 1 | One ballroom - no assignment |
| 2 | Two ballrooms (split by role) - preserved for customer requirement |
| 3 or 4 | Two ballrooms (rotating) - unified behavior, no migration needed |
| 5 | Three ballrooms (rotating) |
| 6 | Four ballrooms (rotating) |

## Rotating Assignment Algorithm

### Goals (soft constraints, in priority order)

1. Honor explicit overrides (heat.ballroom, studio.ballroom preferences)
2. Within a dance block, keep people in the same ballroom (minimize travel)
3. Across blocks, rotate so participants see different judges
4. Must be deterministic - same results on every agenda generation

### Key Concepts

**Block**: A sequence of heats where dance order is increasing. When dance order decreases, a new block begins (due to interleaving pattern from scheduler).

Example with intermix enabled:
- Heat 1: Waltz (order 1)
- Heat 2: Tango (order 2)
- Heat 3: Foxtrot (order 3)
- Heat 4: Waltz (order 1) ← new block
- Heat 5: Tango (order 2)
- ...

**Person-based tracking**: Track person → ballroom rather than entry → ballroom, since people dance with multiple partners.

### State

```ruby
@ballroom_state = {
  person_ballroom: {},    # person_id → current ballroom letter ('A', 'B', 'C', 'D')
  block_number: 0,        # increments when dance order decreases
  last_dance_order: nil   # to detect block boundaries
}
```

### Assignment Logic

For each heat in a heat-number group:

1. **Check heat override**: If `heat.ballroom` is set, use it
2. **Check studio preference**: If `studio.ballroom` is set, use it
3. **Look up person assignments**:
   - Get lead's current ballroom from state
   - Get follow's current ballroom from state
4. **Resolve assignment**:
   - Both nil → compute base assignment with rotation
   - One set → use that ballroom
   - Both set, same → use it
   - Both set, different → conflict resolution

### Conflict Resolution (deterministic)

When lead and follow have different ballroom assignments:

1. Prefer keeping student stationary over professional
2. If both same type, lower `person_id` stays in their ballroom

```ruby
def resolve_ballroom_conflict(heat, lead_room, follow_room)
  lead_is_student = heat.entry.lead.type == 'Student'
  follow_is_student = heat.entry.follow.type == 'Student'

  return lead_room if lead_is_student && !follow_is_student
  return follow_room if follow_is_student && !lead_is_student

  # Both same type - lower person ID stays
  heat.entry.lead_id < heat.entry.follow_id ? lead_room : follow_room
end
```

### Base Assignment for New Participants

When neither person has a ballroom assignment yet:

```ruby
base = heat.entry.id % num_ballrooms
assigned_index = (base + block_number) % num_ballrooms
ballroom_letter = ('A'.ord + assigned_index).chr
```

This ensures:
- Deterministic assignment based on entry ID
- Rotation across blocks (block 0: entry 5 → ballroom 1, block 1: entry 5 → ballroom 2, etc.)

## Implementation Changes

### 1. Settings Page (`app/views/event/settings/options.html.erb`)

Update radio buttons:

```erb
<div class="my-5">
<%= form.label :ballrooms %>
<ul class="ml-6">
<li class="my-2"><%= form.radio_button :ballrooms, 1 %> One ballroom</li>
<li class="my-2"><%= form.radio_button :ballrooms, 2 %> Two ballrooms:
<ul class="ml-8">
<li>Ballroom A: Amateur follower with instructor</li>
<li>Ballroom B: Amateur leader (includes amateur couples)</li>
</ul></li>
<li class="my-2"><%= form.radio_button :ballrooms, 3 %> Two ballrooms (rotating by block)</li>
<li class="my-2"><%= form.radio_button :ballrooms, 5 %> Three ballrooms (rotating by block)</li>
<li class="my-2"><%= form.radio_button :ballrooms, 6 %> Four ballrooms (rotating by block)</li>
</ul>
</div>
```

Note: Values 3 and 4 both map to "two ballrooms rotating" for backwards compatibility.

### 2. Printable Concern (`app/controllers/concerns/printable.rb`)

#### In `generate_agenda`:

Initialize state before the heats loop:

```ruby
@ballroom_state = {
  person_ballroom: {},
  block_number: 0,
  last_dance_order: nil
}
```

Pass state to `assign_rooms` calls.

#### In `assign_rooms`:

Refactor to handle rotating assignment for `ballrooms >= 3` (which includes values 3, 4, 5, 6):

```ruby
def assign_rooms(ballrooms, heats, number, state: nil, preserve_order: false)
  # Existing early returns for solos, pre-assigned, 1 ballroom...

  if ballrooms == 2
    # Existing split-by-role logic
    b = heats.select {|heat| heat.entry.lead.type == "Student"}
    {'A': heats - b, 'B': b}
  else
    # New rotating logic for ballrooms >= 3 (values 3, 4, 5, 6)
    num_rooms = case ballrooms
                when 3, 4 then 2
                when 5 then 3
                when 6 then 4
                end

    assign_rooms_rotating(num_rooms, heats, state)
  end
end

def assign_rooms_rotating(num_rooms, heats, state)
  # Detect new block
  current_order = heats.first&.dance&.order
  if state[:last_dance_order] && current_order && current_order < state[:last_dance_order]
    state[:block_number] += 1
  end
  state[:last_dance_order] = current_order

  result = Hash.new { |h, k| h[k] = [] }

  heats.each do |heat|
    assigned = determine_ballroom(heat, num_rooms, state)
    result[assigned] << heat

    # Update state
    state[:person_ballroom][heat.entry.lead_id] = assigned
    state[:person_ballroom][heat.entry.follow_id] = assigned
  end

  result
end

def determine_ballroom(heat, num_rooms, state)
  # Check overrides first
  return heat.ballroom unless heat.ballroom.blank?

  studio_pref = heat.subject&.studio&.ballroom
  return studio_pref unless studio_pref.blank?

  # Look up existing assignments
  lead_room = state[:person_ballroom][heat.entry.lead_id]
  follow_room = state[:person_ballroom][heat.entry.follow_id]

  if lead_room.nil? && follow_room.nil?
    # New participants - compute base assignment
    base = heat.entry.id % num_rooms
    index = (base + state[:block_number]) % num_rooms
    ('A'.ord + index).chr
  elsif lead_room && follow_room.nil?
    lead_room
  elsif follow_room && lead_room.nil?
    follow_room
  elsif lead_room == follow_room
    lead_room
  else
    resolve_ballroom_conflict(heat, lead_room, follow_room)
  end
end

def resolve_ballroom_conflict(heat, lead_room, follow_room)
  lead_is_student = heat.entry.lead.type == 'Student'
  follow_is_student = heat.entry.follow.type == 'Student'

  return lead_room if lead_is_student && !follow_is_student
  return follow_room if follow_is_student && !lead_is_student

  heat.entry.lead_id < heat.entry.follow_id ? lead_room : follow_room
end
```

### 3. Tests

Add tests in `test/controllers/concerns/printable_test.rb`:

- Test block detection (dance order decrease triggers new block)
- Test person tracking across heats with different partners
- Test conflict resolution (student vs pro, ID tiebreaker)
- Test rotation across blocks
- Test override precedence (heat.ballroom, studio.ballroom)
- Test determinism (same input → same output)
- Test backwards compatibility (values 3 and 4 both work)

### 4. Documentation

Update `app/views/docs/tasks/Ballrooms.md` to explain:

- The rotating assignment approach
- Block concept and how rotation works
- Override precedence
- Why participants may sometimes need to travel (partner conflicts)

## Considerations

### Backwards Compatibility

- Setting values 3 and 4 both treated as "2 ballrooms rotating"
- No database migration required
- Existing events with value 3 or 4 will get new rotating behavior

### Edge Cases

- Solos: Continue to return `{nil => heats}` (no ballroom assignment)
- Formations: Currently only tracks lead/follow; formations participants could be added to state tracking if needed
- Category-level ballroom settings: `cat&.ballrooms` override continues to work

### Future Enhancements

- Track formation participants in state for more accurate conflict detection
- Add UI indicator showing which ballroom a participant is currently in
- Analytics on travel frequency to tune the algorithm
