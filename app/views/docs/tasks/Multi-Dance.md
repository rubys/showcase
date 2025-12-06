# Multi-Dance Competitions

Multi-dance competitions (also called "multis", "all arounds", "triple threats", or "championships") are events where dancers perform multiple dances in sequence and receive a combined ranking. For example, a "Rhythm Championship" might include Cha Cha, Rumba, East Coast Swing, and Bolero.

## Creating a Multi-Dance

1. **Navigate to Dances** from your event's main page
2. **Add a new dance** with a descriptive name (e.g., "Smooth Championship")
3. **Set Heat Length** to the number of dances in the competition (e.g., 4 for a four-dance multi)
4. **Select the component dances** that will be included (e.g., Waltz, Tango, Foxtrot, Viennese Waltz)
5. **Assign to an agenda category** (typically a dedicated "Multi" or "Championships" category)

Once created, the multi-dance appears in the entry form alongside regular dances, allowing students to register for the entire competition.

## Competition Splits (Divisions)

For larger multi-dance events, you may want to split competitors into separate divisions so that, for example, Newcomers don't compete directly against Gold-level dancers. The application supports **layered splits** that can divide a multi-dance by:

1. **Level** - e.g., "Bronze" vs "Silver-Gold"
2. **Age** - e.g., "Under 50" vs "50+"
3. **Couple Type** - e.g., "Pro-Am" vs "Amateur Couple"

Splits are applied in layers: first by level, then optionally by age within each level, then optionally by couple type within each level+age combination.

### Setting Up Competition Splits

1. **Navigate to Entries** and select your multi-dance from the dance filter dropdown
2. **View the Competition Splits table** that appears above the entry list
3. **Use the dropdown menus** to define split points:
   - The **level dropdown** lets you split at any level boundary (e.g., split after Bronze)
   - The **age dropdown** appears once levels are split, letting you add age divisions
   - The **couple type dropdown** lets you separate Pro-Am from Amateur Couples

Each split creates a separate competition with its own rankings. The split name (e.g., "Full Bronze 50+") is displayed to judges during scoring so they know which competition they're ranking.

### Split Behavior

- **Layered structure**: You must split by level before you can split by age, and by age before couple type
- **Collapsing splits**: Use the dropdown to combine splits back together (select "All" or expand the range)
- **Visual indicators**: The entry list shows alternating green/yellow backgrounds to distinguish entries in different splits
- **Duplicate detection**: Red highlighting warns when a dancer appears multiple times in the same split

### How Splits Affect Scheduling

When you schedule heats, the scheduler:
- **Packs compatible splits together**: Multiple splits of the same multi-dance may dance in the same heat number
- **Keeps each split as an atomic unit**: All entries in a split stay together for judging purposes
- **Assigns fractional heat numbers**: Splits within the same heat are distinguished (e.g., heat 45.1, 45.2)

This allows efficient use of floor time while maintaining separate competitions for each division.

### How Splits Affect Scoring

- Each split is judged and ranked independently
- Judges see the split name (e.g., "Silver-Gold 50+ - Pro-Am") when scoring
- Results are calculated separately for each split using the [skating system](../experimental/skating_system_algorithm.md) rules
- The **Summary > Multi-Scores** page shows results grouped by split

## Semi-Finals and Scrutineering

For multi-dances with large fields, you can enable **scrutineering** (semi-finals with callbacks):

1. Edit the multi-dance and check **Scrutineering?**
2. When enabled:
   - If more than 8 couples are in a split, a semi-final round is held first
   - Judges select couples to call back (6 callbacks per judge, maximum 8 total)
   - Finals use ranking (drag-and-drop ordering) instead of checkboxes

See [Scrutineering](../experimental/Scrutineering) for detailed information about callbacks and rankings.