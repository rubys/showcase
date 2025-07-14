# The Skating System Algorithm for Scrutineering

## Overview

The Skating System is the worldwide standard scoring method for ballroom dance competitions. It consists of 11 rules that determine how adjudicator marks are collected and processed during a competition.

## Algorithm Structure

<div style="border: 1px solid black; padding: 1em; text-align: center; margin: 0">
<h4>Part 1: Qualifying Rounds (Rule 1)</h4>
</div>

In qualifying rounds, adjudicators select couples to advance to the next round.

#### **Rule 1: Voting in Qualifying Rounds**
- Each adjudicator votes for exactly the number of couples specified by the Chairman.
- Votes are tallied across all adjudicators.
- Couples with the most votes advance.
- In case of ties at the cutoff point, all tied couples advance.

<div style="border: 1px solid black; padding: 1em; text-align: center; margin: 0">
<h4>Part 2: Final Round Marking (Rules 2-4)</h4>
</div>

These rules govern how adjudicators must mark couples in final rounds.

#### **Rule 2: Complete Placement**
- Each adjudicator must place ALL couples in order of merit in each dance.

#### **Rule 3: Sequential Placement**
- Placements must be sequential: 1st place for the best couple, 2nd for the next best, etc.

#### **Rule 4: No Ties Allowed**
- Adjudicators cannot tie couples for any position.
- Every couple must receive a unique placement from each adjudicator.

<div style="border: 1px solid black; padding: 1em; text-align: center; margin: 0">
<h4>Part 3: Single Dance Calculations (Rules 5-8)</h4>
</div>

These rules determine how to calculate final placements for a single dance based on all adjudicators' marks.

#### **Rule 5: Majority Winner**
- Calculate absolute majority: (Number of adjudicators ÷ 2) + 1
- For each position (starting with 1st), count how many adjudicators placed each couple at that position or better.
- If exactly one couple has absolute majority, they win that position.
- Remove placed couples from further consideration.
- If multiple couples have majority, proceed to Rule 6.
- If no couples have majority, proceed to Rule 8.

#### **Rule 6: Largest Majority**
- Applied when multiple couples have majority for the same position but with different counts.
- The couple with the largest majority (most marks at or better than examining position) wins.
- This couple is removed from further consideration.
- Continue with remaining couples for subsequent positions.

#### **Rule 7: Breaking Equal Majorities**
- Applied when couples have equal majorities (same count of marks) for the same position.

**7(a) Sum of Marks:**
- Sum all marks at or better than the examining position for each tied couple.
- Couple with the lowest sum wins the better position.

**7(b) Equal Sums:**
- When sums are also equal, examine the next place mark.
- Recalculate majorities including the additional place.
- Apply Rules 5-7 recursively until the tie breaks.

**7(c) Unbreakable Ties:**
- When all marks are examined and couples remain tied.
- Couples share the same fractional placement (e.g., two couples tied for 2nd both receive 2.5).

#### **Rule 8: No Majority Found**
- Applied when no couple has majority for the position under review.
- Move to the next examining position (e.g., from 1st to 2nd).
- Continue incrementing until at least one couple achieves majority.
- Once majority is found, apply Rules 5-7 as normal.
- This rule is handled implicitly in the implementation by the examining loop.

<div style="border: 1px solid black; padding: 1em; text-align: center; margin: 0">
<h4>Part 4: Multi-Dance Events (Rule 9)</h4>
</div>

When an event consists of multiple dances, placements from each dance are combined to determine overall results.

#### **Rule 9: Final Summary Compilation**
- Sum each couple's placement marks across all dances (e.g., 1st + 2nd + 1st + 3rd = 7 points).
- Sort couples by total sum (ascending).
- Lowest total wins overall.
- If ties exist, apply Rules 10 and 11.


<div style="border: 1px solid black; padding: 1em; text-align: center; margin: 0">
<h4>Part 5: Tie Breaking in Final Summary (Rules 10-11)</h4>
</div>

When couples have identical total placements after all dances, the following tie-breaking procedures are applied:

#### **Rule 10: Count of Better Placements**
- For each tied couple, count the number of dances where they placed at or above each position (starting from 1st).
- The couple with the most dances at or better than the current position wins the tie.
- If still tied, increment the position and repeat until the tie is broken.
- If all positions are examined and couples remain tied, proceed to Rule 11.

#### **Rule 11: Head-to-Head Comparison**
- Only the tied couples' marks are considered across all dances.
- The single dance placement algorithm (Rules 5-8) is re-applied to these couples.
- The couple ranked 1st in this head-to-head wins the tie.
- If still tied, couples share the same final position, and fractional placements may be assigned.



<div style="border: 1px solid black; padding: 1em; text-align: center; margin: 0">
<h4>Implementation Notes</h4>
</div>

### Key Data Structures:
- **Scores**: Stored with heat_id, judge_id, slot (dance number), and value (placement)
- **Rankings**: Hash mapping Entry objects to their final rank
- **Explanations**: Optional detailed trace of algorithm decisions for debugging

### Algorithm Flow:
1. **Single Dance Placement** (`Heat.rank_placement`):
   - Iterates through positions 1 to max, examining each
   - Uses recursive runoff function for tie-breaking
   - Returns rankings hash and optional explanations

2. **Multi-Dance Compilation** (`Heat.rank_summaries`):
   - Sums placements across all dances (Rule 9)
   - Breaks ties using count of better placements (Rule 10)
   - Falls back to head-to-head comparison (Rule 11)

### Special Cases:
- **Fractional Placements**: When couples tie after all rules, rank = base + (count-1)/2.0
- **Set Return**: Rule 11 may return a Set of backs when ties are unbreakable
- **Focused Runoff**: Rule 7(b) uses focused=true flag to limit examination to tied couples
- **Empty Scores**: Algorithm handles cases where no couples have been marked

## Validation Rules
1. All couples must be placed by all adjudicators
2. No duplicate placements allowed from single adjudicator
3. Majority = (Number of judges ÷ 2) + 1
4. All ties must be resolved using rules in sequence 5→6→7→8

References:

* [Tabulating DanceSport Competition Marks](https://www.dancepartner.com/articles/dancesport-skating-system.asp)
* [The Skating System Study Guide](https://dancesport.org.au/accreditation/candidate_info/scrutineering_tutorial.pdf)