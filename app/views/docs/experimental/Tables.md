# Tables – Seating Assignments

The Tables feature helps you arrange seating for your event.

**Overview:**

- Enter people and studios, and pair studios as desired.
- If you want separate tables for meals, go to **Settings**, select the **Prices** tab, and create options for each meal. For arranging tables, prices are not important.
- Assign people to tables using one of the two methods described below.
- From the main page, click on **Studios**, find a studio larger than the table size, click on the studio, then **Tables**, and review or adjust the tables for this studio for each meal.
- For last-minute changes, add or remove a person. When you add a person, you can select their tables. Note that their table may be full.

There are two table assignment algorithms available:

## Regular Assignment (Assign People to Tables)

The **Assign People to Tables** button follows this prioritized list:

1. People from the same studio are placed at the same table when possible, then at adjacent tables if there is overflow.
2. People from paired studios are placed at the same table when possible, then at adjacent tables if needed.
3. Tables that aren't full are combined when possible, including small studios and overflow from large studios.
4. Tables that need to be adjacent are placed into a grid. This can be complex with multiple studio pairs or when overflow from large studios is combined.
5. Remaining tables fill in any gaps.
6. Event staff are seated together and not combined with any other studio.

This approach prioritizes seating people together over filling every seat. For example, if you have three studios with five people each and a table size of eight, you could seat everyone at two tables, but at least one studio would be split. The rules above avoid this by allocating three tables. This situation is rare, but more likely with a table size of eight than ten.

## Pack Assignment (Pack People in Tables)

The **Pack People in Tables** button uses an aggressive packing algorithm that prioritizes table efficiency:

1. Groups studios with their paired studios (components) to maintain relationships where possible.
2. Processes components sequentially, filling tables to capacity before starting new ones.
3. Avoids leaving exactly one empty seat per table (prevents 9-person tables when table size is 10).
4. Never splits studios with 3 or fewer people to ensure no one sits alone from their studio.
5. May split larger studios across multiple tables when necessary for optimal packing.
6. Uses the same intelligent grid placement as regular assignment for spatial arrangement.

The pack algorithm typically creates fewer tables than regular assignment (closer to theoretical minimum) but may be more aggressive about splitting large studios. It's ideal when maximizing table utilization is more important than keeping every studio together.

## Choosing Between Algorithms

- Use **Regular Assignment** when preserving studio relationships is the top priority
- Use **Pack Assignment** when maximizing table efficiency and minimizing total tables is more important
- Both algorithms maintain studio pair relationships and use intelligent grid placement for optimal spatial arrangement

If you don't like the results from either algorithm, click **Reset** to remove all tables and try the other approach or start over.

You can also add tables individually and select a studio to seat people from. If there are unfilled seats, click on the table and add another studio. There is a "Create additional tables if needed" checkbox that you can use to create a packed set of tables with the studio you select and all of its paired studios. For maximum density, you can edit the final table and add more studios, or click **New Table** to create a new group.

The **Arrange Tables** feature lets you drag tables to match the room layout or organize tables differently. As you hover over a table, all connected tables will be highlighted.

**Renumber** assigns new numbers left to right, then top to bottom. For a different numbering, return to the Tables page, click on a table, and change its number.

Once done, return to the Studios page to see table assignments. If a studio has multiple tables, click the tables column to view those tables, and drag and drop people to move them to a different table.

When editing a person, you can see and change their table assignment or remove them from any table.

On the publish page, you will see a button to get a printable list of table assignments, and a page that shows tables by studio. If there are any issues (for example, people without seats or studios not seated together), a list of issues will be included in the table list report.

*This feature is experimental. Please report any issues or suggestions for improvement.*