# Scheduling

The scheduling system automatically generates heats (competitive dance sessions) based on your entries, settings, and agenda configuration. This guide explains how to create and manage your event schedule.

## Quick Start

1. Navigate to the **Heats** page
2. Click the **Redo** button to generate/regenerate the schedule
3. Review the generated heats and make adjustments as needed

## Understanding the Scheduling Process

The scheduler uses a two-pass algorithm:
- **First pass**: Minimizes the total number of heats while respecting your constraints
- **Second pass**: Balances heat sizes for better flow and judging

### What the Scheduler Considers

1. **Dancer Conflicts**: Ensures no dancer is scheduled in two places at once
2. **Studio Conflicts**: Prevents studio representatives from competing against each other (if configured)
3. **Age/Level Mixing**: Controls whether beginners and advanced dancers compete together
4. **Heat Size Limits**: Respects minimum and maximum couples per heat
5. **Dance Order**: Interleaves different dance styles within categories

## Configuring Schedule Settings

### Global Settings (Settings → Heats Tab)

- **Heat Interval**: Time between the start of consecutive heats (e.g., 90 seconds)
- **Minimum Couples**: Smallest allowed heat size (typically 1-2)
- **Maximum Couples**: Largest allowed heat size (typically 6-8)
- **Mix Levels**: Whether newcomers and advanced dancers can compete together
- **Mix Ages**: Whether different age groups can compete together

### Per-Category Settings (Agenda Page)

Each agenda category can override global settings:
- Set specific heat size limits for categories
- Control mixing rules for specific portions of your event
- Add start times to calculate scheduled times for all heats

## Step-by-Step Scheduling

### 1. Prepare Your Data

Before scheduling:
- Ensure all entries are complete
- Verify dancer information is correct
- Set up your agenda categories
- Configure any special dance categories (multi-dance, championships)

### 2. Configure Settings

1. Go to **Settings → Heats**
2. Set your preferred heat interval (time between heats)
3. Configure minimum/maximum couples per heat
4. Decide on level/age mixing rules
5. Save your settings

### 3. Set Up Agenda

1. Navigate to **Agenda**
2. Create categories for different portions of your event (e.g., "Morning Bronze", "Afternoon Silver")
3. Assign dances to appropriate categories
4. Set start times for categories to generate a timed schedule
5. Override heat limits for specific categories if needed

### 4. Generate Schedule

1. Go to **Heats**
2. Click **Redo** to generate the schedule
3. The system will:
   - Group entries into heats
   - Assign heat numbers
   - Calculate times (if start times are set)
   - Interleave dance styles

### 5. Review and Adjust

After generation:
- Check heat sizes are appropriate
- Verify no scheduling conflicts
- Look for any unusually small or large heats
- Use manual reordering if needed (see [Reordering](./Reordering))

## Common Scenarios

### Scheduling a Small Studio Showcase

1. Use larger maximum heat sizes (8-10 couples)
2. Enable level mixing to combine heats
3. Set shorter heat intervals (60-75 seconds)

### Scheduling a Large Multi-Studio Event

1. Use standard heat sizes (6-8 couples max)
2. Disable level mixing for fair competition
3. Set standard intervals (90 seconds)
4. Use multiple ballrooms if needed (see [Ballrooms](./Ballrooms))

### Scheduling with Solos and Formations

1. Solos are scheduled within their assigned categories
2. Order solos on the [Solos](./Solos) page before scheduling
3. The scheduler respects manual solo ordering
4. Formations follow the same rules as solos

### Scheduling Multi-Dance Competitions

[Multi-dance competitions](./Multi-Dance) (championships, all arounds) have special scheduling behavior:

1. **Competition Splits** are kept together as atomic units - all entries in a split dance in the same heat
2. **Compatible splits** may be packed into the same heat number to reduce total heat count
3. Splits within the same heat are distinguished by fractional numbers (e.g., 45.1, 45.2)
4. Each split is judged and ranked independently

To configure splits before scheduling, go to **Entries** and select your multi-dance.

## Troubleshooting

### "Cannot create valid schedule"
- Too many constraints (try relaxing level/age mixing)
- Heat size limits too restrictive
- Check for entries with impossible conflicts

### Heats Too Small/Large
- Adjust minimum/maximum couple settings
- Enable/disable level mixing
- Check category-specific overrides

### Schedule Takes Too Long
- **Single person with too many entries**: Often an instructor with many students creates a bottleneck (they can only be on the floor once per heat)
- **Settings too restrictive**: Allow more couples on the floor, move age/level sliders right to enable mixing, consider allowing open/closed mixing
- **Heat interval too long**: Reduce the time between start of consecutive heats

### Dancers in Wrong Order
- Check dance assignments to categories
- Verify agenda category order
- Look for category overrides on specific dances

## Best Practices

1. **Schedule Early, Adjust Often**: Generate an initial schedule early, then refine as entries change
2. **Use Categories Wisely**: Break your event into logical sections (by level, time of day)
3. **Monitor Heat Sizes**: Aim for consistent heat sizes for better flow
4. **Plan for Changes**: Keep some flexibility for last-minute entries and scratches
5. **Test Settings**: Try different configurations to find what works for your event

## Related Topics

- [Agenda](./Agenda) - Organizing your event structure
- [Multi-Dance](./Multi-Dance) - Championship events with competition splits
- [Settings](./Settings) - Configuring heat parameters
- [Reordering](./Reordering) - Manual schedule adjustments
- [Ballrooms](./Ballrooms) - Multi-floor scheduling
- [Scratches and Walk-ons](./Scratches-and-Walk-ons) - Last-minute changes