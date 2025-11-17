# Student Judge Assignments by Category

Student Judge Assignments is an experimental feature that allows students to be assigned to specific judges on a **per-category basis** rather than per-heat. This approach prioritizes judge variety across categories while ensuring consistent scoring within each category.

## Overview

In traditional scoring, each heat is scored independently by all judges. With category-based assignments:

* **Students are assigned to one judge per category** - Each student receives a single consolidated score for all heats within a category
* **Judge variety is maximized** - The system prioritizes assigning different judges across categories, so students experience multiple judging perspectives throughout the event
* **Student partnerships preserved** - Students dancing together in a category are always assigned to the same judge for that category
* **Simplified scoring for judges** - Judges score each student once per category instead of once per heat

This feature is particularly useful for:

* Events with multiple judges (3+ recommended)
* Students competing in multiple categories
* Events wanting to maximize judge variety while maintaining scoring consistency

## Enabling Category Scoring

### Step 1: Enable Event-Level Feature

Navigate to **Settings** → **Event Options** and check:

* ✓ **Enable student judge assignments by category?**

This enables the feature for your event but doesn't activate it for any categories yet.

### Step 2: Configure Per-Category

For each category where you want to use category scoring:

1. Navigate to **Dances** from your event's main page
2. Click on a **category name** (e.g., "Smooth", "Rhythm", "Standard")
3. Check ✓ **Use category scoring (one score per student per category)?**
4. Click **Update Category**

Categories default to using category scoring when the event-level feature is enabled. You can selectively disable it for specific categories by unchecking the option.

### Mixed Configuration

You can use category scoring for some categories and traditional per-heat scoring for others in the same event:

* **Solo category** might use per-heat scoring (each solo scored individually)
* **Closed categories** might use category scoring (one score per student per category)
* **Open categories** might use traditional scoring (all judges score each heat)

The system automatically uses the appropriate scoring method based on the category configuration.

### Scoring Interface

**For judges**, the scoring interface adapts based on the heat composition:

1. **Navigate heats normally** using the heat list or navigation buttons
2. **View heat details** showing all couples competing
3. **Enter scores** using your preferred method (radio buttons, cards, rankings)

**Amateur Couple Support:**

When both the lead and follow are students (amateur couple), the heat appears **twice in the scoring interface** - once for each student:

* **First row/card**: Shows the lead student being evaluated, with follow as partner
* **Second row/card**: Shows the follow student being evaluated, with lead as partner
* **Each student scored independently**: The lead and follow receive separate category scores
* **Column headers adapt**: When column order is set to show Student/Partner, the student being evaluated always appears in the "Student" column

Example:

Heat 40 - Amateur Couple (both students):

      ┌─────────────────────────────────────────┐
      │ Student        Partner      Category    │
      ├─────────────────────────────────────────┤
      │ Alice Student  Bob Student  Adult - NC  │ ← Alice being scored
      │ Bob Student    Alice Student Adult - NC │ ← Bob being scored
      └─────────────────────────────────────────┘

## Assignment Algorithm Details

The assignment algorithm optimizes for two goals in order:

1. **Judge variety across categories** (primary goal)
   * Students should see different judges in different categories when possible
   * Uses 1000× penalty multiplier for judge repeats
   * Example: With 4 categories and 3 judges, achieved 81.1% judge variety (students saw 2-3 different judges)

2. **Balanced judge workload** (secondary goal)
   * Distributes students evenly across judges within each category
   * Minimizes coefficient of variation (CV) in judge assignments
   * Example: With 39 students and 3 judges, achieved 2.7% CV (near-perfect balance)

**Partnership handling:**

* Connected component analysis identifies student groups who dance together
* Entire partnership assigned to same judge within a category
* **Amateur couples** (both lead and follow are students) are each scored separately but assigned to the same judge within the category
* Small adjustments made after initial assignment to improve balance

## Reports and Results

### Viewing Scores

**From Judge Pages:**

* Judges see their assigned students listed by category
* Category scores appear once per student (not repeated for each heat)
* Scores display alongside student information

**From Summary Page:**

* Results show category scores for enabled categories
* Per-heat scores show for traditional categories
* Formatting automatically adapts based on score type

### Assignment Report

After assigning judges, you'll see statistics showing:

* Number of students assigned per judge in each category
* Distribution balance (coefficient of variation)
* Overall judge variety percentage across categories

## Things to Be Aware Of

* **Judge variety depends on configuration**: With only 2 judges, students will see the same judges repeatedly. 3+ judges recommended for meaningful variety.

* **Category score appears on all heats**: When a judge views any heat for a student in a category-scored category, they see that student's category score. Changing the score updates it for all heats.

* **Partnerships must be consistent**: If students dance together in some heats but not others within the same category, the system groups them together. This may result in larger assignment units than expected.

* **Amateur couples appear twice**: When both the lead and follow are students (amateur couple), the heat appears twice in the scoring interface - once for each student. Each student receives their own independent category score. This allows both students in an amateur couple to be evaluated separately while competing together.

* **Offline scoring supported**: The [Offline Scoring](./Offline-Scoring) feature works with category scoring - judges can score offline and scores sync when connectivity returns.

## Related Topics

* [Scoring](../tasks/Scoring) - General scoring system documentation
* [Settings](../tasks/Settings) - Event configuration and options
* [Judge Role Guide](../roles/Judge) - Complete judge instructions
* [Offline Scoring](./Offline-Scoring) - Scoring without internet connectivity

---

**Status: Experimental** - This feature has been validated with test scenarios but is awaiting real-world usage at actual events. Please report any issues or unexpected behavior.
