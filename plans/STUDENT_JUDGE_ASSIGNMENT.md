# Student-to-Judge Assignment Plan

**Purpose:** Implement an alternative judge assignment strategy that assigns each student to a specific judge for all their heats throughout the event, rather than assigning judges per-heat per-couple.

## Overview

### Current System (Per-Heat Assignment)

The existing `assign_judges` feature creates Score records for each heat independently:
- **Location**: `app/controllers/people_controller.rb:785-886` (`assign_judges` action)
- **Strategy**: For each heat, assigns one judge per couple based on:
  - Balancing judge workload across heats
  - Avoiding conflicts (judges excluded from specific dancers)
  - Ballroom assignments (judges restricted to specific ballrooms)
- **Result**: Different couples may have different judges in different heats

### New System (Per-Student Assignment)

The proposed feature assigns each student to one judge for the entire event:
- **Strategy**: Each student gets assigned to a specific judge, and that judge scores all heats involving that student
- **Key Constraint**: Students who dance together (student-student partnerships) must be assigned to the same judge
- **Result**: Consistent judge-student relationships throughout the event

### When to Use Each System

| System | Best For |
|--------|----------|
| **Per-Heat** | Events where judge availability varies, ballroom-specific judging, or minimizing conflicts with specific couples |
| **Per-Student** | Events where judges want consistency with students throughout the event, easier tracking of student progress |

## Requirements

### Functional Requirements

1. **Student Grouping**: Identify students who dance together and must share the same judge
2. **Load Balancing**: Distribute students and heats as evenly as possible across judges
3. **Score Generation**: Create Score records for all heats based on student assignments
4. **Compatibility**: Work alongside existing per-heat assignment without conflicts

### Constraints

1. **Student-Student Partnerships**: If Student A dances with Student B in any entry, both must be assigned to the same judge
2. **Transitivity**: If A dances with B, and B dances with C, then A, B, and C must all be assigned to the same judge
3. **Balance**: Minimize variance in both student count and heat count across judges

## Algorithm Design

### Phase 1: Identify Assignment Units

**Goal**: Group students who must be assigned together

```ruby
def build_assignment_units
  # 1. Build partnership graph
  student_partnerships = Hash.new { |h, k| h[k] = Set.new }

  Person.where(type: 'Student').includes(:lead_entries, :follow_entries).each do |student|
    # Check all entries where this student participates
    (student.lead_entries + student.follow_entries).each do |entry|
      # If the partner is also a student, they must share a judge
      partner = entry.lead_id == student.id ? entry.follow : entry.lead
      if partner.type == 'Student'
        student_partnerships[student.id].add(partner.id)
        student_partnerships[partner.id].add(student.id)
      end
    end
  end

  # 2. Find connected components using BFS
  groups = []
  visited = Set.new

  student_partnerships.keys.each do |student_id|
    next if visited.include?(student_id)

    # BFS to find all connected students
    group = Set.new
    queue = [student_id]

    while queue.any?
      current = queue.shift
      next if visited.include?(current)

      visited.add(current)
      group.add(current)

      student_partnerships[current].each do |partner_id|
        queue.push(partner_id) unless visited.include?(partner_id)
      end
    end

    groups << group.to_a
  end

  # 3. Add solo students (those with no student partners)
  all_students = Person.where(type: 'Student').pluck(:id)
  all_students.each do |student_id|
    unless visited.include?(student_id)
      groups << [student_id]
    end
  end

  # 4. Calculate heat count for each group
  groups.map do |student_ids|
    heat_count = Heat.joins(:entry)
      .where(number: 1..)
      .where('entries.lead_id IN (?) OR entries.follow_id IN (?)', student_ids, student_ids)
      .count

    {
      students: student_ids,
      student_count: student_ids.count,
      heat_count: heat_count
    }
  end
end
```

### Phase 2: Assign Groups to Judges

**Goal**: Balance load across judges using greedy algorithm

```ruby
def assign_units_to_judges(units, judge_ids)
  # Sort units by heat count descending (largest first)
  # This "first-fit decreasing" heuristic gives better balance
  sorted_units = units.sort_by { |u| -u[:heat_count] }

  # Initialize judge loads
  judge_loads = judge_ids.map do |id|
    [id, { student_count: 0, heat_count: 0, units: [] }]
  end.to_h

  # Greedy assignment: assign each unit to least-loaded judge
  sorted_units.each do |unit|
    # Find judge with minimum heat count
    min_judge_id = judge_loads.min_by { |id, load| load[:heat_count] }.first

    # Assign unit to this judge
    judge_loads[min_judge_id][:student_count] += unit[:student_count]
    judge_loads[min_judge_id][:heat_count] += unit[:heat_count]
    judge_loads[min_judge_id][:units] << unit
  end

  judge_loads
end
```

### Phase 3: Generate Score Records

**Goal**: Create Score records based on student assignments

```ruby
def generate_scores_from_assignments(judge_loads)
  # Build student-to-judge mapping
  student_to_judge = {}
  judge_loads.each do |judge_id, load|
    load[:units].each do |unit|
      unit[:students].each do |student_id|
        student_to_judge[student_id] = judge_id
      end
    end
  end

  # Create scores for all heats
  heats = Heat.where(number: 1..)
    .where.not(category: 'Solo')
    .includes(entry: [:lead, :follow])

  Score.transaction do
    heats.each do |heat|
      judges_for_heat = Set.new

      # Add judge for lead if student
      if heat.entry.lead.type == 'Student'
        judge_id = student_to_judge[heat.entry.lead_id]
        judges_for_heat.add(judge_id) if judge_id
      end

      # Add judge for follow if student
      if heat.entry.follow.type == 'Student'
        judge_id = student_to_judge[heat.entry.follow_id]
        judges_for_heat.add(judge_id) if judge_id
      end

      # Create Score records
      judges_for_heat.each do |judge_id|
        Score.find_or_create_by!(heat_id: heat.id, judge_id: judge_id)
      end
    end
  end
end
```

## Implementation Plan

### Step 1: Add Controller Action

**File**: `app/controllers/people_controller.rb`

Add new action parallel to existing `assign_judges`:

```ruby
def assign_students_to_judges
  # Verify this is a judge being assigned
  judges = Person.where(type: 'Judge', present: true).pluck(:id)

  if judges.count < 2
    redirect_to person_path(params[:id]), alert: "Need at least 2 judges for assignment"
    return
  end

  # Clear existing assignments in unscored heats
  delete_judge_assignments_in_unscored_heats

  # Build assignment units
  units = build_assignment_units

  # Assign to judges
  judge_loads = assign_units_to_judges(units, judges)

  # Generate Score records
  generate_scores_from_assignments(judge_loads)

  # Prepare statistics for notice
  stats = judge_loads.map do |judge_id, load|
    judge = Person.find(judge_id)
    "#{judge.name}: #{load[:student_count]} students, #{load[:heat_count]} heats"
  end.join('; ')

  redirect_to person_path(params[:id]), notice: "Students assigned: #{stats}"
end

private

# Helper methods go here (build_assignment_units, etc.)
```

### Step 2: Add Route

**File**: `config/routes.rb`

Add route alongside existing `assign_judges`:

```ruby
resources :people do
  member do
    post :assign_judges
    post :assign_students_to_judges  # NEW
    post :reset_assignments
    # ... other routes
  end
end
```

### Step 3: Update Judge UI

**File**: `app/views/people/_judge_section.html.erb`

Add second button in the judge assignment section:

```erb
<div class="mt-4">
  <h3 class="font-bold text-lg mb-2">Judge Assignments</h3>

  <div class="flex gap-2 items-center">
    <%= button_to "Assign Judges to Couples",
        assign_judges_person_path(@person),
        method: :post,
        class: "rounded-lg py-2 px-4 bg-blue-600 text-white font-medium cursor-pointer",
        title: "Assigns judges independently for each heat, balancing across heats" %>

    <%= button_to "Assign Students to Judges",
        assign_students_to_judges_person_path(@person),
        method: :post,
        class: "rounded-lg py-2 px-4 bg-green-600 text-white font-medium cursor-pointer",
        title: "Assigns each student to one judge for all their heats" %>

    <%= button_to "Reset Assignments",
        reset_assignments_person_path(@person),
        method: :post,
        class: "rounded-lg py-2 px-4 bg-gray-400 text-white font-medium cursor-pointer",
        data: { confirm: "Clear all judge assignments?" } %>
  </div>

  <div class="mt-2 text-sm text-gray-600">
    <p><strong>Assign Judges to Couples:</strong> Each heat assigned independently (current behavior)</p>
    <p><strong>Assign Students to Judges:</strong> Each student assigned to same judge throughout event</p>
  </div>
</div>
```

### Step 4: Add Analysis Tool (Optional)

**File**: `plans/analyze_student_assignments.rb`

The analysis script is included in the plans directory for preview and testing:

```ruby
#!/usr/bin/env ruby
# Usage: RAILS_APP_DB=event-name bin/rails runner plans/analyze_student_assignments.rb

require_relative '../config/environment'

# ... (existing analysis code)
# Shows:
# - Student groups that must stay together
# - Balance simulation
# - Statistics on assignment quality
```

This tool helps event organizers preview assignment balance before executing.

## Edge Cases and Considerations

### Edge Case 1: Student Dances with Multiple Student Partners

**Scenario**: Student A dances with Student B in some entries, and with Student C in other entries

**Handling**: All three (A, B, C) form one group and get assigned to the same judge

**Reason**: Transitivity of the partnership constraint

### Edge Case 2: Unbalanced Groups

**Scenario**: One group has 200 heats, but total heats / judge count = 150

**Handling**: Assign large group to one judge; that judge gets fewer solo students to balance

**Example**: Barcelona event has:
- Group of 4 students (200 heats) → Judge 1
- Judge 1 gets fewer solo students to compensate
- Final balance: 481, 469, 469 heats (excellent)

### Edge Case 3: Single Judge

**Scenario**: Event has only one judge

**Handling**: Button should be disabled or show warning

**Implementation**: Check `Person.where(type: 'Judge', present: true).count >= 2` before allowing assignment

### Edge Case 4: Student with No Heats

**Scenario**: Student exists but has no active heats

**Handling**: Exclude from assignment (don't count in groups)

**Implementation**: Filter to only students with `heats.where(number: 1..).any?`

### Edge Case 5: Mixed Solo and Student Heats

**Scenario**: Solo heats exist alongside student heats

**Handling**: Solo heats are excluded from this assignment (only Open/Closed/Multi heats)

**Reason**: Solos have separate scoring system and review process

## Testing Strategy

### Unit Tests

**File**: `test/controllers/people_controller_test.rb`

```ruby
test "assign_students_to_judges creates balanced assignments" do
  # Setup: 3 judges, 10 students (2 student-student pairs, 6 solo students)
  # Execute: assign_students_to_judges
  # Assert:
  #   - All students have scores for their heats
  #   - Student pairs have same judge
  #   - Heat counts are balanced (within 20% of mean)
end

test "assign_students_to_judges handles student-student partnerships" do
  # Setup: Students A and B dance together
  # Execute: assign_students_to_judges
  # Assert: All heats involving A or B have same judge_id
end

test "assign_students_to_judges requires at least 2 judges" do
  # Setup: Only 1 judge
  # Execute: assign_students_to_judges
  # Assert: Redirects with alert
end
```

### Integration Tests

**File**: `test/integration/student_judge_assignment_test.rb`

```ruby
test "complete student assignment workflow" do
  # Setup: Realistic event with varied entries
  # Execute: Full workflow through UI
  # Assert:
  #   - Assignments created successfully
  #   - Balance meets criteria
  #   - Judges can score assigned heats
end
```

### Manual Testing

**Checklist** (to be added to `plans/STUDENT_JUDGE_ASSIGNMENT_TESTING.md`):

1. ✓ Assign students to judges with Barcelona data
2. ✓ Verify balance statistics match simulation
3. ✓ Check student-student pairs have same judge in all heats
4. ✓ Verify judges see correct heats in their scoring interface
5. ✓ Test reset functionality
6. ✓ Verify switching between per-heat and per-student assignment works
7. ✓ Test with events of different sizes (small: <20 students, large: >50 students)

## Performance Considerations

### Algorithm Complexity

- **Building groups**: O(S + E) where S = students, E = entries with BFS
- **Assigning to judges**: O(G log G) where G = groups (sorting)
- **Creating scores**: O(H × J) where H = heats, J = judges per heat (typically 1)

### Expected Performance

For typical event:
- 40 students, 200 entries, 1400 heats
- Grouping: ~50ms
- Assignment: <1ms
- Score creation: ~200ms
- **Total: <300ms** (well within acceptable range)

### Large Event Scaling

For large event:
- 200 students, 1000 entries, 10000 heats
- Grouping: ~200ms
- Assignment: ~5ms
- Score creation: ~2000ms (2 seconds)
- **Total: <3 seconds** (acceptable for one-time operation)

## Data Migration

**No schema changes required** - uses existing Score table for storage.

## Rollback Plan

If issues arise:

1. **Immediate**: Use "Reset Assignments" button to clear scores
2. **Alternative**: Use original "Assign Judges to Couples" button
3. **Emergency**: Manually delete Score records: `Score.where(heat: Heat.where.not(number: ...0)).destroy_all`

No data loss risk since this only creates Score records (which can be regenerated).

## Documentation Updates

### User Documentation

**File**: `docs/tasks/Settings.md` (or similar)

Add section explaining:
- Difference between per-heat and per-student assignment
- When to use each approach
- How to use the buttons
- How to verify assignments

### Developer Documentation

**File**: `CLAUDE.md`

Add note in "Key Components" section about the two assignment strategies.

## Success Metrics

Assignment quality is measured by:

1. **Balance**: Coefficient of variation (CV) for heat distribution
   - Excellent: CV < 5%
   - Good: CV < 10%
   - Acceptable: CV < 20%

2. **Student Distribution**: Max difference in student count between judges
   - Excellent: Diff ≤ 2
   - Good: Diff ≤ 4
   - Acceptable: Diff ≤ 6

3. **Constraint Satisfaction**: 100% (all student-student pairs together)

## Future Enhancements

Potential improvements for future iterations:

1. **Assignment Preview**: Show balance statistics before creating scores
2. **Manual Override**: Allow drag-and-drop to reassign specific students
3. **Conflict Avoidance**: Respect existing exclude relationships (Person.exclude_id)
4. **Ballroom Support**: Handle judges restricted to specific ballrooms
5. **Weighted Balance**: Allow prioritizing student count vs heat count balance
6. **Assignment Persistence**: Add `assigned_judge_id` field to Person for explicit tracking

## References

- Current implementation: `app/controllers/people_controller.rb:785-886`
- Score model: `app/models/score.rb`
- Entry model: `app/models/entry.rb`
- Heat model: `app/models/heat.rb`
- Barcelona analysis results: See analysis script output above
