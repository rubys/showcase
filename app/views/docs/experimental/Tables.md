# Tables - Optimal Seating Assignments

<div data-controller="info-box">
  <div class="info-button">ⓘ</div>
  <ul class="info-box">
    <li>Use the <strong>Assign People to Tables</strong> button to automatically optimize table assignments</li>
    <li>The algorithm minimizes wasted seats while keeping people from the same studio together</li>
    <li>Paired studios (like Raleigh ↔ Raleigh-DT) are positioned adjacent to each other</li>
    <li>Tables are numbered sequentially following the physical room layout</li>
    <li>You can manually adjust table positions using drag-and-drop on the arrange page</li>
    <li>Set the default table size in the form at the bottom of the tables page</li>
  </ul>
</div>

The Tables feature provides intelligent seating management for your showcase event, automatically optimizing table assignments to minimize wasted seats while keeping people from the same studio together.

## Key Features

### Automatic Assignment Algorithm
- **Optimal space utilization**: Achieves 94%+ seat efficiency using advanced bin packing
- **Studio proximity**: Groups people from the same studio at nearby tables
- **Studio pairs**: Positions paired studios (defined in StudioPair model) adjacent to each other
- **Mixed table optimization**: When studios must share tables, positions them to minimize travel for all parties
- **Sequential numbering**: Tables are numbered 1, 2, 3... following the physical room layout

### Manual Controls
- **Drag-and-drop arrangement**: Use the arrange page to manually position tables on a grid
- **Configurable table size**: Set the default number of seats per table (typically 8-12)
- **Individual table editing**: Adjust specific table details and view assigned people

## How to Use

### Setting Up Tables
1. Go to the **Tables** page from the main navigation
2. Set your default table size using the form at the bottom (typically 10 seats)
3. Click **Assign People to Tables** to run the optimization algorithm

### Viewing Results
After assignment, you'll see:
- Tables numbered sequentially (1, 2, 3...)
- Grid layout showing physical table positions
- Studio names grouped together when possible
- Number of people assigned to each table

### Manual Adjustments
1. Click **Arrange Tables** to access the drag-and-drop interface
2. Drag tables to new grid positions as needed
3. Click **Save** to apply your changes
4. Use **Reset** to clear all positions and start over

## Algorithm Details

The assignment algorithm works in several phases:

1. **Perfect Fits**: Studios that exactly match table size get their own tables
2. **Optimal Packing**: Remaining people are packed efficiently to minimize empty seats
3. **Studio Pairing**: Related studios (like Raleigh ↔ Raleigh-DT) are positioned adjacently
4. **Mixed Table Placement**: Tables with multiple studios are positioned near all constituent studios
5. **Sequential Numbering**: Tables are renumbered based on their final physical positions

### Example Results
For a typical event with 104 people and 10-seat tables:
- **Before**: 14 tables with 36 wasted seats (74% efficiency)
- **After**: 11 tables with 6 wasted seats (94% efficiency)
- **Studio proximity**: Maximum distance between studio tables ≤ 5 positions
- **Paired studios**: Adjacent positioning (distance = 1)

## Technical Notes

### Database Structure
- `Table` model with `number`, `row`, `col`, and `size` fields
- `Event.table_size` for configurable default table capacity
- `StudioPair` model defining which studios should be positioned together
- `Person.table_id` foreign key for table assignments

### Grid Layout
- Tables positioned on an 8-column grid (adjustable)
- Row and column coordinates determine physical layout
- Empty grid positions are allowed for irregular room shapes

### Mixed Tables
When people from different studios share a table, the algorithm:
- Calculates weighted distances to minimize travel for all affected people
- Applies fairness penalties to prevent extreme splits across the room
- Considers the number of people from each studio when positioning

## Best Practices

1. **Run assignment early** in your event planning to establish baseline seating
2. **Review results** and make manual adjustments for special requirements
3. **Consider table size** - larger tables reduce efficiency but may improve comfort
4. **Use studio pairs** to define related studios that should sit together
5. **Test different configurations** using the drag-and-drop interface

## Troubleshooting

**Too many empty seats?**
- Reduce the default table size
- Check for studios marked as "Event Staff" (excluded from assignments)

**Studios too far apart?**
- Use the StudioPair model to define related studios
- Manually adjust using the arrange interface

**Tables in wrong order?**
- The algorithm automatically numbers tables 1-N following room layout
- Use drag-and-drop to reposition tables, then re-run assignment

---

*This feature is experimental. Please report any issues or suggestions for improvement.*