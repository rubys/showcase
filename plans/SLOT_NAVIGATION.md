# Slot Navigation Specification

**Purpose:** Define navigation behavior for multi-dance heats in the SPA scoring interface.

## Overview

Multi-dance heats (e.g., "Bronze 2 Dance", "Full Bronze 3 Dance") contain multiple child dances scored sequentially. Judges score each dance separately, navigating through "slots" within the same heat number.

## Data Model

### Database Structure

**Dances Table:**
- `heat_length` (INTEGER): Number of child dances in multi-dance event (e.g., 2, 3, 4)
- `semi_finals` (BOOLEAN): Whether this dance uses scrutineering (semi-finals + finals)

**Multi Table:**
- Links parent dance (e.g., "Bronze 2 Dance") to child dances (e.g., Waltz, Tango)
- `parent_id` → Dance ID of parent
- `dance_id` → Dance ID of child

**Heats Table:**
- `number` (DECIMAL): Heat number (e.g., 5, 42.5)
- `category` (VARCHAR): "Multi" for multi-dance heats, "Open", "Closed", "Solo", etc. for others
- `dance_id` → Points to parent dance for Multi heats

### Slot Calculation

**Basic Multi-dance:**
```
heat_length = 2  (e.g., Waltz, Tango)
max_slots = 2
slots: [1, 2]
```

**With Scrutineering (Semi-finals + Finals):**
```
heat_length = 3  (e.g., Waltz, Tango, Foxtrot)
uses_scrutineering = true
max_slots = heat_length * 2 = 6
slots: [1, 2, 3, 4, 5, 6]
  - Slots 1-3: Semi-finals (Waltz, Tango, Foxtrot)
  - Slots 4-6: Finals (Waltz, Tango, Foxtrot)
```

**Scrutineering Logic:**
- Applied when `semi_finals` is true on parent dance
- Only if subject count > 8 (otherwise no semi-finals needed)
- Doubles the slot count

## Navigation Algorithm

### Next Button

```javascript
function calculateNext(currentHeat, currentSlot, allHeats) {
  if (currentHeat.category === 'Multi') {
    const parentDance = currentHeat.dance.parent || currentHeat.dance;
    let maxSlots = parentDance.heat_length || 0;

    // Check if scrutineering applies
    const usesScrutineering = parentDance.semi_finals;
    const subjectCount = currentHeat.subjects.length;
    const isFinal = currentSlot > parentDance.heat_length;

    if (usesScrutineering && (!isFinal || currentSlot > parentDance.heat_length)) {
      maxSlots *= 2;
    }

    if (currentSlot < maxSlots) {
      // More slots in current heat
      return {
        heat: currentHeat.number,
        slot: currentSlot + 1
      };
    } else {
      // Move to next heat number
      const nextHeat = getNextHeat(currentHeat.number, allHeats);
      if (!nextHeat) return null;

      if (nextHeat.category === 'Multi') {
        const nextParent = nextHeat.dance.parent || nextHeat.dance;
        if (nextParent.heat_length) {
          return { heat: nextHeat.number, slot: 1 };
        }
      }

      return { heat: nextHeat.number, slot: null };
    }
  } else {
    // Non-multi heat: just go to next heat number
    const nextHeat = getNextHeat(currentHeat.number, allHeats);
    if (!nextHeat) return null;

    if (nextHeat.category === 'Multi') {
      return { heat: nextHeat.number, slot: 1 };
    }

    return { heat: nextHeat.number, slot: null };
  }
}
```

### Previous Button

```javascript
function calculatePrev(currentHeat, currentSlot, allHeats) {
  if (currentHeat.category === 'Multi') {
    if (currentSlot > 1) {
      // More slots in current heat (going backward)
      return {
        heat: currentHeat.number,
        slot: currentSlot - 1
      };
    } else {
      // Move to previous heat number
      const prevHeat = getPrevHeat(currentHeat.number, allHeats);
      if (!prevHeat) return null;

      if (prevHeat.category === 'Multi') {
        const prevParent = prevHeat.dance.parent || prevHeat.dance;
        let maxSlots = prevParent.heat_length || 0;

        const prevUsesScrutineering = prevParent.semi_finals;
        const prevSubjectCount = prevHeat.subjects.length;

        if (prevUsesScrutineering && prevSubjectCount > 8) {
          maxSlots *= 2;
        }

        return { heat: prevHeat.number, slot: maxSlots };
      }

      return { heat: prevHeat.number, slot: null };
    }
  } else {
    // Non-multi heat: just go to previous heat number
    const prevHeat = getPrevHeat(currentHeat.number, allHeats);
    if (!prevHeat) return null;

    if (prevHeat.category === 'Multi') {
      const prevParent = prevHeat.dance.parent || prevHeat.dance;
      let maxSlots = prevParent.heat_length || 0;

      const prevUsesScrutineering = prevParent.semi_finals;
      const prevSubjectCount = prevHeat.subjects.length;

      if (prevUsesScrutineering && prevSubjectCount > 8) {
        maxSlots *= 2;
      }

      return { heat: prevHeat.number, slot: maxSlots };
    }

    return { heat: prevHeat.number, slot: null };
  }
}
```

## URL Structure

**Standard Heat:**
```
/scores/123/spa?heat=5
```

**Multi-dance Heat with Slot:**
```
/scores/123/spa?heat=5&slot=2
```

**URL Parameter Handling:**
- `heat` (required): Heat number (decimal allowed, e.g., 42.5)
- `slot` (optional): Slot number for multi-dance heats
- Default slot: 1 if heat is Multi category and no slot specified

## UI Considerations

### Navigation Footer

**Display:**
```
[← Previous]  Heat 5.2 / 5.3  [Next →]
```

For multi-dance heats:
- Show current slot / max slots
- Format: `Heat {number}.{slot} / {number}.{maxSlots}`

For non-multi heats:
- Show just heat number
- Format: `Heat {number}`

### Keyboard Shortcuts

- Arrow Left: Previous (same logic as Previous button)
- Arrow Right: Next (same logic as Next button)
- Numbers 1-9: Jump to slot N within current heat (if Multi)

## Edge Cases

### Case 1: First Heat, First Slot
```
Current: Heat 1, Slot 1
Previous: null (disabled)
Next: Heat 1, Slot 2 (if Multi with heat_length >= 2)
      or Heat 2 (if not Multi or heat_length = 1)
```

### Case 2: Last Heat, Last Slot
```
Current: Heat 251, Slot 3 (maxSlots = 3)
Previous: Heat 251, Slot 2
Next: null (disabled)
```

### Case 3: Boundary Between Heats
```
Current: Heat 5, Slot 3 (maxSlots = 3)
Next: Heat 6, Slot 1 (if Heat 6 is Multi)
      or Heat 6 (no slot if not Multi)
```

### Case 4: Scrutineering Transition
```
Current: Heat 10, Slot 3 (semi-finals, heat_length = 3)
Next: Heat 10, Slot 4 (finals begin)

Current: Heat 10, Slot 6 (finals complete, heat_length = 3, maxSlots = 6)
Next: Heat 11, Slot 1 or Heat 11 (depending on category)
```

### Case 5: Heat Without heat_length Set
```
Multi category heat with heat_length = 0 or null
→ Treat as non-multi (no slot navigation)
→ Move directly to next/prev heat number
```

## Implementation Notes

### Required Data in JSON

For each heat in the JSON response:
```json
{
  "number": 5,
  "category": "Multi",
  "dance": {
    "name": "Bronze 2 Dance",
    "parent_id": 33,
    "heat_length": 2,
    "semi_finals": false
  },
  "subjects": [...]
}
```

### Score Submission

When posting scores for multi-dance heats:
```javascript
POST /scores/:judge/post
{
  "heat": 5,     // Heat ID (not heat number)
  "slot": 2,     // Slot number
  "score": "1",
  "comments": "",
  "good": "",
  "bad": ""
}
```

Server uses `find_or_create_by(judge_id:, heat_id:, slot:)` for idempotent updates.

### Client-Side State

The HeatPage component needs to track:
- Current heat number
- Current slot (if Multi)
- Max slots for current heat
- Next/prev heat numbers and slots

## Testing Scenarios

1. **Basic Multi Navigation**
   - Heat 5 (Bronze 2 Dance, heat_length = 2)
   - Start at slot 1, click Next → slot 2
   - Click Next → Heat 6 slot 1 or Heat 6

2. **Scrutineering Navigation**
   - Heat 10 (Full Bronze 3 Dance, heat_length = 3, semi_finals = true, subjects > 8)
   - Start at slot 1, click Next 5 times → slots 2, 3, 4, 5, 6
   - Slot 6 → Next → Heat 11

3. **Mixed Heat Types**
   - Heat 3 (Solo) → Next → Heat 4 (Multi, slot 1)
   - Heat 4, slot 2 → Next → Heat 5 (Open)

4. **Backward Navigation**
   - Heat 6 → Prev → Heat 5, slot 2 (last slot)
   - Heat 5, slot 1 → Prev → Heat 4

5. **Keyboard Navigation**
   - Arrow keys work same as buttons
   - Number keys jump to specific slot within heat

## Ruby Reference (scores_controller.rb:439-487)

The JavaScript implementation should mirror the Ruby logic:
- Lines 440-445: Determine `effective_heat_length`
- Lines 447-466: Calculate `@next`
- Lines 468-487: Calculate `@prev`

Key differences for SPA:
- Ruby uses database queries to get prev/next heats
- JavaScript uses in-memory heat list from JSON
- Both should produce identical navigation behavior
