# The Skating System Algorithm for DanceSport Scrutineering

## Overview

The Skating System is the worldwide standard scoring method for DanceSport competitions. It consists of 11 rules that determine how adjudicator marks are collected and processed during a competition.

## Algorithm Structure

### Part 1: Qualifying Rounds (Rules 1-4)

#### Rule 1: Voting in Qualifying Rounds
- **Input**: Number of couples to recall (specified by Chairman)
- **Process**: Each adjudicator votes for exactly the specified number of couples
- **Output**: List of recalled couples per adjudicator

#### Recall Calculation Algorithm:
1. Count total votes received by each couple across all adjudicators
2. Sort couples by vote count (descending)
3. Select top N couples as specified by Chairman
4. If ties exist at the cutoff point, include all tied couples

### Part 2: Final Round Marking (Rules 2-4)

#### Rule 2: Final Round Placement
- Each adjudicator must place ALL couples in order of merit in each dance

#### Rule 3: Sequential Placement
- 1st place → best couple
- 2nd place → second best couple
- Continue sequentially for all couples

#### Rule 4: No Ties Allowed
- Adjudicators cannot tie couples for any position
- Every couple must have a unique placement from each adjudicator

### Part 3: Single Dance Calculations (Rules 5-8)

#### Rule 5: Majority Winner
**Algorithm**:
1. Calculate absolute majority needed: (Number of adjudicators ÷ 2) + 1
2. For position P (starting with 1st):
   - Count how many adjudicators placed each couple at position P or better
   - Couple with absolute majority wins position P
   - Mark couple as placed
   - Continue to next position

#### Rule 6: Largest Majority
**When**: Multiple couples have majority for same position
**Algorithm**:
1. Compare majority counts for tied couples
2. Couple with largest majority gets the position
3. Other couples get subsequent positions

#### Rule 7: Breaking Equal Majorities
**When**: Couples have equal majorities for same position

**Rule 7(a) - Equal Majorities**:
1. Add together marks that form the majority for each couple
2. Couple with lowest aggregate gets the position
3. Continue for remaining tied couples

**Rule 7(b) - Equal Majorities AND Aggregates**:
1. Include next lower place mark in calculation
2. Recalculate majorities
3. If still tied, continue including lower marks until tie breaks
4. Couple with greater majority wins

#### Rule 8: No Majority Found
**When**: No couple has majority for position under review
**Algorithm**:
1. Include next place marks in calculation (e.g., for 1st place, include 1st AND 2nd)
2. Recalculate majorities
3. If still no majority, continue including lower marks
4. Apply Rules 5-7 once majority is found

### Part 4: Multi-Dance Events (Rule 9)

#### Rule 9: Final Summary Compilation
**Algorithm**:
1. For each couple:
   - Sum their placement marks across all dances
   - Example: 1st + 2nd + 1st + 3rd = 7 points
2. Sort couples by total (ascending)
3. Lowest total wins overall
4. If ties exist, apply Rules 10 and 11

### Part 5: Tie Breaking in Final Summary (Rules 10-11)

#### Rule 10: Breaking Final Summary Ties
**When**: Couples have same aggregate in final summary
**Algorithm**:
1. For tied couples at position P:
   - Count how many dances each couple placed P or better
   - Couple with most dances at P or better wins
2. If still tied after checking all positions:
   - Sum the place marks in dances where couples achieved P or better
   - Couple with lowest sum wins
3. Continue for all tied positions

#### Rule 11: Ultimate Tie Breaking
**When**: Couples remain tied after Rule 10
**Algorithm**:
1. Compare head-to-head results between tied couples only
2. Count how many times each couple beat the other(s)
3. Couple who won most head-to-head comparisons gets better position
4. If still tied:
   - Apply same process to next group of tied couples
   - As last resort, couples may share the same final position

## Implementation Notes

### Special Cases:
- **Fractional Placements**: When couples tie after all rules, they share positions (e.g., 2.5)
- **Recalled in Some Dances**: Couple may advance in some dances but not others
- **Missing Adjudicator**: Recalculate majority based on actual panel size

## Validation Rules
1. All couples must be placed by all adjudicators
2. No duplicate placements allowed from single adjudicator
3. Majority calculations must use correct formula
4. All ties must be resolved using appropriate rules in sequence
