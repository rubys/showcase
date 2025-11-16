# Student-to-Judge Assignment Plan (Per-Category with Judge Variety)

**Purpose:** Implement per-category judge assignment for students with a single consolidated score per category, prioritizing judge variety across categories.

## Overview

### Current System (Per-Heat Assignment)

The existing `assign_judges` feature creates Score records for each heat independently:
- **Location**: `app/controllers/people_controller.rb:785-886` (`assign_judges` action)
- **Strategy**: For each heat, assigns one judge per couple based on workload balance and conflict avoidance
- **Result**: Different couples may have different judges in different heats

### New System (Per-Category Assignment with Consolidated Scoring)

The proposed feature assigns each student to one judge per category:
- **Strategy**: Each student gets assigned to a specific judge for each category, prioritizing judge variety across categories
- **Key Constraint**: Students who dance together (student-student partnerships) must be assigned to the same judge within that category
- **Scoring**: Students receive a single Score record per category (not per heat) containing feedback and comments for all heats in that category
- **Result**: Consistent judge-student relationships within each category, with variety across categories

### When to Use Each System

| System | Best For |
|--------|----------|
| **Per-Heat** | Events where judge availability varies, ballroom-specific judging, or professional/amateur pairings |
| **Per-Category** | Events where students dance with students, judges want to provide consolidated feedback per category, and judge variety across categories is desired |

## Requirements

### Functional Requirements

1. **Per-Category Assignment**: Judges assigned to students on a per-category basis (not per-event)
2. **Judge Variety Priority**: Maximize exposure to different judges across categories for each student
3. **Student Grouping**: Identify students who dance together within each category and must share the same judge
4. **Load Balancing**: Distribute students and heats as evenly as possible across judges
5. **Consolidated Scoring**: One Score record per student per category (covering all their heats in that category)
6. **Configuration**: Event-level enable flag and category-level opt-in

### Constraints

1. **Student-Student Partnerships**: If Student A dances with Student B in any heat within a category, both must be assigned to the same judge for that category
2. **Transitivity**: If A dances with B, and B dances with C in a category, then A, B, and C must all be assigned to the same judge for that category
3. **Balance**: Minimize variance in both student count and heat count across judges
4. **Variety**: Maximize the number of unique judges each student sees across all categories

## Data Model Approach: Overloading `Score.heat_id`

### Convention

Instead of adding new columns, we overload the existing `heat_id` field:

- **`heat_id > 0`**: Normal per-heat scoring (existing behavior)
- **`heat_id < 0`**: Per-category scoring (new behavior, where `heat_id = -category_id`)

### Rationale

- **Minimal schema changes**: No migration required
- **Backward compatible**: Existing scores continue to work
- **Simple implementation**: Most code paths require minimal changes
- **Clear distinction**: Sign of the ID indicates the scoring type

### Helper Methods (Score model)

```ruby
# app/models/score.rb

def category_score?
  heat_id.negative?
end

def per_heat_score?
  heat_id.positive?
end

def actual_category_id
  -heat_id if category_score?
end

def actual_category
  Category.find(actual_category_id) if category_score?
end

def actual_heat
  Heat.find(heat_id) if per_heat_score?
end

# Scope for category scores
scope :category_scores, -> { where('heat_id < 0') }
scope :heat_scores, -> { where('heat_id > 0') }
```

### Validation

Ensure `category_id` is never 0 (to avoid `-0 == 0` confusion):

```ruby
# app/models/category.rb
validates :id, numericality: { greater_than: 0, only_integer: true }, on: :create
```

## Algorithm Design

### Phase 1: Identify Assignment Units Per Category

**Goal**: Group students who must be assigned together within each category

```ruby
def build_category_assignment_units(category)
  student_ids = Person.where(type: 'Student').pluck(:id)

  # Get all closed heats in this category with students
  heats = Heat.where(number: 1.., category: 'Closed')
    .joins(:entry, :dance)
    .where(dances: { closed_category_id: category.id })
    .where('entries.lead_id IN (?) OR entries.follow_id IN (?)', student_ids, student_ids)

  # Build partnership graph for this category
  student_partnerships = Hash.new { |h, k| h[k] = Set.new }
  student_heat_count = Hash.new(0)

  heats.each do |heat|
    lead_id = heat.entry.lead_id
    follow_id = heat.entry.follow_id

    lead_is_student = student_ids.include?(lead_id)
    follow_is_student = student_ids.include?(follow_id)

    if lead_is_student
      student_heat_count[lead_id] += 1

      # If both are students, they must share a judge
      if follow_is_student
        student_partnerships[lead_id].add(follow_id)
        student_partnerships[follow_id].add(lead_id)
      end
    end

    student_heat_count[follow_id] += 1 if follow_is_student
  end

  # Find connected components using BFS
  groups = find_connected_components(student_partnerships, student_heat_count.keys)

  # Create assignment units
  groups.map do |student_ids|
    {
      students: student_ids,
      student_count: student_ids.count,
      heat_count: student_ids.sum { |id| student_heat_count[id] }
    }
  end
end

def find_connected_components(partnerships, all_student_ids)
  groups = []
  visited = Set.new

  partnerships.keys.each do |student_id|
    next if visited.include?(student_id)

    # BFS to find all connected students
    group = Set.new
    queue = [student_id]

    while queue.any?
      current = queue.shift
      next if visited.include?(current)

      visited.add(current)
      group.add(current)

      partnerships[current].each do |partner_id|
        queue.push(partner_id) unless visited.include?(partner_id)
      end
    end

    groups << group.to_a if group.any?
  end

  # Add solo students (those with no student partners in this category)
  all_student_ids.each do |student_id|
    unless visited.include?(student_id)
      groups << [student_id]
    end
  end

  groups
end
```

### Phase 2: Assign Units to Judges with Variety Priority

**Goal**: Balance load across judges while maximizing judge variety for each student

```ruby
def assign_categories_to_judges_with_variety(categories, judge_ids)
  # Track which judge each student has been assigned in previous categories
  student_judge_history = Hash.new { |h, k| h[k] = [] }

  results = {}

  categories.each do |category|
    # Get assignment units for this category
    units = build_category_assignment_units(category)

    # Sort by heat count descending (largest first for better bin-packing)
    units.sort_by! { |u| -u[:heat_count] }

    # Initialize judge loads for this category
    judge_loads = judge_ids.map do |id|
      [id, { student_count: 0, heat_count: 0, units: [] }]
    end.to_h

    # Greedy assignment with variety scoring
    units.each do |unit|
      # For each judge, calculate a score based on:
      # 1. Heat balance (lower is better)
      # 2. Judge variety penalty (how many students in this unit have seen this judge)
      best_judge_id = judge_ids.min_by do |judge_id|
        heat_score = judge_loads[judge_id][:heat_count]

        # Count how many students in this unit have seen this judge before
        repeat_count = unit[:students].count { |sid| student_judge_history[sid].include?(judge_id) }
        variety_penalty = repeat_count * 1000  # Make variety a strong factor

        heat_score + variety_penalty
      end

      # Assign unit to best judge
      judge_loads[best_judge_id][:student_count] += unit[:student_count]
      judge_loads[best_judge_id][:heat_count] += unit[:heat_count]
      judge_loads[best_judge_id][:units] << unit

      # Update student history
      unit[:students].each do |student_id|
        student_judge_history[student_id] << best_judge_id
      end
    end

    results[category.id] = judge_loads
  end

  results
end
```

### Phase 3: Generate Score Records

**Goal**: Create Score records for category assignments (negative heat_id)

```ruby
def generate_category_scores(assignment_results)
  Score.transaction do
    assignment_results.each do |category_id, judge_loads|
      judge_loads.each do |judge_id, load|
        load[:units].each do |unit|
          unit[:students].each do |student_id|
            # Create one score per student per category
            # Use negative category_id to indicate category scoring
            Score.find_or_create_by!(
              heat_id: -category_id,
              judge_id: judge_id,
              person_id: student_id
            )
          end
        end
      end
    end
  end
end
```

**Note**: We use `person_id` to track which student this category score is for. This field may need to be added if it doesn't exist.

### Alternative: Use Existing Judge-Person Relationship

If `person_id` doesn't exist on Score, we can infer the student from the heats:

```ruby
# When looking up category scores for display:
def category_scores_for_student(category_id, student_id)
  Score.where(heat_id: -category_id)
    .joins('JOIN heats ON heats.id = ABS(scores.heat_id)')
    .joins('JOIN entries ON entries.id = heats.entry_id')
    .where('entries.lead_id = ? OR entries.follow_id = ?', student_id, student_id)
end
```

However, adding `person_id` to Score is cleaner and more explicit.

## Configuration

### Event-Level Configuration

Add a new event option to enable student judge assignments:

```ruby
# app/models/event.rb
# Add new boolean attribute (requires migration):
# add_column :events, :student_judge_assignments, :boolean, default: false

validates :student_judge_assignments, inclusion: { in: [true, false] }
```

### Category-Level Configuration

Add a boolean to Category to opt-in to per-category scoring:

```ruby
# app/models/category.rb
# Add new boolean attribute (requires migration):
# add_column :categories, :use_category_scoring, :boolean, default: false

validates :use_category_scoring, inclusion: { in: [true, false] }
```

### Usage Logic

```ruby
# Only create category scores for categories with use_category_scoring = true
eligible_categories = Category.where(use_category_scoring: true)

if Event.first.student_judge_assignments?
  results = assign_categories_to_judges_with_variety(eligible_categories, judge_ids)
  generate_category_scores(results)
end
```

## SPA Changes

The Web Components-based judge scoring interface needs significant updates to support per-category scoring.

### 1. JSON API Changes

**Endpoint**: `GET /scores/:judge_id/heats.json`

**Current Response**:
```json
{
  "heats": [
    {
      "id": 123,
      "number": 5,
      "dance": "Waltz",
      "category": "Closed",
      "couples": [...]
    }
  ]
}
```

**New Response** (when category scoring is enabled):
```json
{
  "heats": [
    {
      "id": 123,
      "number": 5,
      "dance": "Waltz",
      "category": "Closed",
      "category_id": 1,
      "use_category_scoring": false,
      "couples": [...]
    }
  ],
  "category_scores": [
    {
      "category_id": 2,
      "category_name": "Rhythm",
      "students": [
        {
          "person_id": 45,
          "name": "John Doe",
          "heat_count": 12,
          "heat_ids": [234, 235, 236, ...],
          "existing_score": {
            "good": 8,
            "comments": "Great progress!"
          }
        }
      ]
    }
  ]
}
```

### 2. Controller Changes

**File**: `app/controllers/scores_controller.rb`

Update the `heats` action to include category scoring data:

```ruby
def heats
  judge = Person.find(params[:judge_id])

  # Existing heat-based scores
  heats = Heat.where(number: 1..)
    .joins(:scores)
    .where(scores: { judge_id: judge.id })
    .includes(:dance, entry: [:lead, :follow])

  # New category-based scores
  category_scores = Score.category_scores
    .where(judge_id: judge.id)
    .includes(:actual_category)

  # Group category scores by category
  categories_data = category_scores.group_by(&:actual_category_id).map do |cat_id, scores|
    category = Category.find(cat_id)

    {
      category_id: cat_id,
      category_name: category.name,
      students: scores.map do |score|
        person = Person.find(score.person_id)

        # Find all heats for this student in this category
        student_heats = Heat.where(number: 1.., category: 'Closed')
          .joins(:entry, :dance)
          .where(dances: { closed_category_id: cat_id })
          .where('entries.lead_id = ? OR entries.follow_id = ?', person.id, person.id)

        {
          person_id: person.id,
          name: person.name,
          heat_count: student_heats.count,
          heat_ids: student_heats.pluck(:id),
          existing_score: {
            good: score.good,
            bad: score.bad,
            value: score.value,
            comments: score.comments
          }
        }
      end
    }
  end

  render json: {
    heats: heats.as_json(include: { ... }),
    category_scores: categories_data
  }
end
```

### 3. HeatDataManager Changes

**File**: `app/javascript/heat_data_manager.js`

Add support for category scores in the data manager:

```javascript
class HeatDataManager {
  constructor() {
    this.heats = [];
    this.categoryScores = [];  // NEW
    // ... existing code
  }

  async loadData(judgeId) {
    const response = await fetch(`/scores/${judgeId}/heats.json`);
    const data = await response.json();

    this.heats = data.heats;
    this.categoryScores = data.category_scores || [];  // NEW

    // Store in IndexedDB
    await this.saveToIndexedDB();
  }

  // NEW: Get category score for a student
  getCategoryScore(categoryId, personId) {
    const category = this.categoryScores.find(c => c.category_id === categoryId);
    if (!category) return null;

    return category.students.find(s => s.person_id === personId);
  }

  // NEW: Save category score
  async saveCategoryScore(categoryId, personId, scoreData) {
    const scoreRecord = {
      heat_id: -categoryId,  // Negative to indicate category score
      judge_id: this.judgeId,
      person_id: personId,
      ...scoreData
    };

    if (navigator.onLine) {
      await this.postScore(scoreRecord);
    } else {
      await this.queueScore(scoreRecord);
    }

    // Update local cache
    this.updateCategoryScoreCache(categoryId, personId, scoreData);
  }

  updateCategoryScoreCache(categoryId, personId, scoreData) {
    const category = this.categoryScores.find(c => c.category_id === categoryId);
    if (!category) return;

    const student = category.students.find(s => s.person_id === personId);
    if (student) {
      student.existing_score = { ...student.existing_score, ...scoreData };
    }
  }
}
```

### 4. New Component: `category-score.js`

Create a new component for category scoring interface:

```javascript
// app/javascript/components/category-score.js

class CategoryScore extends HTMLElement {
  connectedCallback() {
    this.render();
    this.attachEventListeners();
  }

  render() {
    const categoryId = this.getAttribute('category-id');
    const personId = this.getAttribute('person-id');
    const studentData = window.heatDataManager.getCategoryScore(categoryId, personId);

    if (!studentData) {
      this.innerHTML = '<p>No data available</p>';
      return;
    }

    const score = studentData.existing_score || {};

    this.innerHTML = `
      <div class="category-score-container">
        <div class="student-info">
          <h3>${studentData.name}</h3>
          <p>${studentData.heat_count} heats in this category</p>
        </div>

        <div class="score-inputs">
          <label>
            Good (0-10):
            <input type="number"
                   name="good"
                   min="0"
                   max="10"
                   value="${score.good || ''}"
                   class="score-input">
          </label>

          <label>
            Comments:
            <textarea name="comments"
                      rows="5"
                      class="score-input">${score.comments || ''}</textarea>
          </label>
        </div>

        <div class="heat-preview">
          <h4>Heats covered by this score:</h4>
          <ul>
            ${studentData.heat_ids.map(id => `<li>Heat #${id}</li>`).join('')}
          </ul>
        </div>

        <button class="save-button">Save Category Score</button>
      </div>
    `;
  }

  attachEventListeners() {
    const saveButton = this.querySelector('.save-button');
    const inputs = this.querySelectorAll('.score-input');

    saveButton.addEventListener('click', async () => {
      const categoryId = parseInt(this.getAttribute('category-id'));
      const personId = parseInt(this.getAttribute('person-id'));

      const scoreData = {
        good: parseInt(this.querySelector('[name="good"]').value) || null,
        comments: this.querySelector('[name="comments"]').value || ''
      };

      await window.heatDataManager.saveCategoryScore(categoryId, personId, scoreData);

      // Show confirmation
      this.showSaveConfirmation();
    });

    // Auto-save on input change (debounced)
    inputs.forEach(input => {
      input.addEventListener('input', this.debounce(() => {
        saveButton.click();
      }, 1000));
    });
  }

  debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
      const later = () => {
        clearTimeout(timeout);
        func(...args);
      };
      clearTimeout(timeout);
      timeout = setTimeout(later, wait);
    };
  }

  showSaveConfirmation() {
    // Visual feedback that save was successful
    const button = this.querySelector('.save-button');
    const originalText = button.textContent;
    button.textContent = '✓ Saved';
    button.classList.add('saved');

    setTimeout(() => {
      button.textContent = originalText;
      button.classList.remove('saved');
    }, 2000);
  }
}

customElements.define('category-score', CategoryScore);
```

### 5. Navigation Changes (`heat-page.js`)

Update navigation to include category scoring views:

```javascript
// app/javascript/components/heat-page.js

class HeatPage extends HTMLElement {
  render() {
    const { heats, categoryScores } = window.heatDataManager;

    // Existing heat navigation
    const heatList = this.renderHeatList(heats);

    // NEW: Category scoring navigation
    const categoryList = this.renderCategoryList(categoryScores);

    this.innerHTML = `
      <nav class="scoring-navigation">
        <div class="nav-section">
          <h2>Per-Heat Scoring</h2>
          ${heatList}
        </div>

        ${categoryScores.length > 0 ? `
          <div class="nav-section">
            <h2>Per-Category Scoring</h2>
            ${categoryList}
          </div>
        ` : ''}
      </nav>

      <div id="scoring-content">
        <!-- Heat or category score component rendered here -->
      </div>
    `;
  }

  renderCategoryList(categoryScores) {
    return categoryScores.map(category => `
      <div class="category-item">
        <h3>${category.category_name}</h3>
        <ul>
          ${category.students.map(student => `
            <li>
              <a href="#category/${category.category_id}/student/${student.person_id}">
                ${student.name} (${student.heat_count} heats)
                ${student.existing_score?.comments ? '✓' : ''}
              </a>
            </li>
          `).join('')}
        </ul>
      </div>
    `).join('');
  }

  handleNavigation(hash) {
    // Existing heat navigation
    if (hash.startsWith('#heat/')) {
      const heatId = parseInt(hash.split('/')[1]);
      this.showHeat(heatId);
    }
    // NEW: Category navigation
    else if (hash.startsWith('#category/')) {
      const [_, categoryId, __, personId] = hash.split('/');
      this.showCategoryScore(parseInt(categoryId), parseInt(personId));
    }
  }

  showCategoryScore(categoryId, personId) {
    const content = this.querySelector('#scoring-content');
    content.innerHTML = `
      <category-score
        category-id="${categoryId}"
        person-id="${personId}">
      </category-score>
    `;
  }
}
```

### 6. IndexedDB Schema Update

Update IndexedDB to store category scores separately:

```javascript
// In HeatDataManager.setupIndexedDB()

const db = await openDB('JudgeScoringDB', 2, {  // Increment version
  upgrade(db, oldVersion, newVersion) {
    // Existing heats store
    if (!db.objectStoreNames.contains('heats')) {
      db.createObjectStore('heats', { keyPath: 'id' });
    }

    // NEW: Category scores store
    if (!db.objectStoreNames.contains('categoryScores')) {
      const store = db.createObjectStore('categoryScores', {
        keyPath: ['category_id', 'person_id']
      });
      store.createIndex('category_id', 'category_id');
      store.createIndex('person_id', 'person_id');
    }

    // Existing scores queue
    if (!db.objectStoreNames.contains('scoreQueue')) {
      db.createObjectStore('scoreQueue', {
        keyPath: 'id',
        autoIncrement: true
      });
    }
  }
});
```

## Implementation Plan

### Step 1: Database Migration

**File**: `db/migrate/YYYYMMDDHHMMSS_add_student_judge_assignment_fields.rb`

```ruby
class AddStudentJudgeAssignmentFields < ActiveRecord::Migration[8.0]
  def change
    # Event-level configuration
    add_column :events, :student_judge_assignments, :boolean, default: false

    # Category-level configuration
    add_column :categories, :use_category_scoring, :boolean, default: false

    # Score person tracking (if not exists)
    add_column :scores, :person_id, :integer unless column_exists?(:scores, :person_id)
    add_index :scores, :person_id unless index_exists?(:scores, :person_id)

    # Index for category scores
    add_index :scores, [:heat_id, :judge_id, :person_id],
              name: 'index_scores_on_heat_judge_person',
              unique: true
  end
end
```

### Step 2: Update Score Model

**File**: `app/models/score.rb`

Add helper methods and validations:

```ruby
class Score < ApplicationRecord
  belongs_to :heat
  belongs_to :judge, class_name: 'Person'
  belongs_to :person, optional: true  # Student receiving this score

  # Category scoring helpers
  def category_score?
    heat_id.negative?
  end

  def per_heat_score?
    heat_id.positive?
  end

  def actual_category_id
    -heat_id if category_score?
  end

  def actual_category
    Category.find(actual_category_id) if category_score?
  end

  def actual_heat
    Heat.find(heat_id) if per_heat_score?
  end

  # Scopes
  scope :category_scores, -> { where('heat_id < 0') }
  scope :heat_scores, -> { where('heat_id > 0') }

  # Validation
  validates :person_id, presence: true, if: :category_score?

  # Override empty? check for category scores
  def empty?
    if category_score?
      good.nil? && bad.nil? && value.nil? && comments.blank?
    else
      super
    end
  end
end
```

### Step 3: Add Controller Action

**File**: `app/controllers/people_controller.rb`

Add new action for student judge assignment:

```ruby
def assign_students_to_judges_by_category
  # Verify we have judges
  judges = Person.where(type: 'Judge', present: true).pluck(:id)

  if judges.count < 2
    redirect_to person_path(params[:id]),
                alert: "Need at least 2 judges for assignment"
    return
  end

  # Get categories with category scoring enabled
  categories = Category.where(use_category_scoring: true).order(:order)

  if categories.empty?
    redirect_to person_path(params[:id]),
                alert: "No categories configured for category scoring"
    return
  end

  # Clear existing category score assignments
  Score.category_scores.destroy_all

  # Perform assignment
  assignment_results = assign_categories_to_judges_with_variety(categories, judges)

  # Generate Score records
  generate_category_scores(assignment_results)

  # Prepare statistics
  stats = []
  assignment_results.each do |category_id, judge_loads|
    category = Category.find(category_id)
    stats << "#{category.name}:"

    judge_loads.each do |judge_id, load|
      judge = Person.find(judge_id)
      stats << "  #{judge.name}: #{load[:student_count]} students, #{load[:heat_count]} heats"
    end
  end

  redirect_to person_path(params[:id]),
              notice: "Students assigned by category:\n#{stats.join("\n")}"
end

private

def assign_categories_to_judges_with_variety(categories, judge_ids)
  # Track judge assignments for variety
  student_judge_history = Hash.new { |h, k| h[k] = [] }
  results = {}

  categories.each do |category|
    units = build_category_assignment_units(category)
    units.sort_by! { |u| -u[:heat_count] }

    judge_loads = judge_ids.index_with do |id|
      { student_count: 0, heat_count: 0, units: [] }
    end

    units.each do |unit|
      best_judge_id = judge_ids.min_by do |judge_id|
        heat_score = judge_loads[judge_id][:heat_count]
        repeat_count = unit[:students].count { |sid| student_judge_history[sid].include?(judge_id) }
        variety_penalty = repeat_count * 1000

        heat_score + variety_penalty
      end

      judge_loads[best_judge_id][:student_count] += unit[:student_count]
      judge_loads[best_judge_id][:heat_count] += unit[:heat_count]
      judge_loads[best_judge_id][:units] << unit

      unit[:students].each do |student_id|
        student_judge_history[student_id] << best_judge_id
      end
    end

    results[category.id] = judge_loads
  end

  results
end

def build_category_assignment_units(category)
  student_ids = Person.where(type: 'Student').pluck(:id)

  heats = Heat.where(number: 1.., category: 'Closed')
    .joins(:entry, :dance)
    .where(dances: { closed_category_id: category.id })
    .where('entries.lead_id IN (?) OR entries.follow_id IN (?)', student_ids, student_ids)

  student_partnerships = Hash.new { |h, k| h[k] = Set.new }
  student_heat_count = Hash.new(0)

  heats.each do |heat|
    lead_id = heat.entry.lead_id
    follow_id = heat.entry.follow_id

    lead_is_student = student_ids.include?(lead_id)
    follow_is_student = student_ids.include?(follow_id)

    if lead_is_student
      student_heat_count[lead_id] += 1
      if follow_is_student
        student_partnerships[lead_id].add(follow_id)
        student_partnerships[follow_id].add(lead_id)
      end
    end

    student_heat_count[follow_id] += 1 if follow_is_student
  end

  groups = find_connected_components(student_partnerships, student_heat_count.keys)

  groups.map do |student_ids|
    {
      students: student_ids,
      student_count: student_ids.count,
      heat_count: student_ids.sum { |id| student_heat_count[id] }
    }
  end
end

def find_connected_components(partnerships, all_student_ids)
  groups = []
  visited = Set.new

  partnerships.keys.each do |student_id|
    next if visited.include?(student_id)

    group = Set.new
    queue = [student_id]

    while queue.any?
      current = queue.shift
      next if visited.include?(current)

      visited.add(current)
      group.add(current)

      partnerships[current].each do |partner_id|
        queue.push(partner_id) unless visited.include?(partner_id)
      end
    end

    groups << group.to_a if group.any?
  end

  all_student_ids.each do |student_id|
    groups << [student_id] unless visited.include?(student_id)
  end

  groups
end

def generate_category_scores(assignment_results)
  Score.transaction do
    assignment_results.each do |category_id, judge_loads|
      judge_loads.each do |judge_id, load|
        load[:units].each do |unit|
          unit[:students].each do |student_id|
            Score.find_or_create_by!(
              heat_id: -category_id,
              judge_id: judge_id,
              person_id: student_id
            )
          end
        end
      end
    end
  end
end
```

### Step 4: Update Routes

**File**: `config/routes.rb`

```ruby
resources :people do
  member do
    post :assign_judges
    post :assign_students_to_judges_by_category  # NEW
    post :reset_assignments
    # ... other routes
  end
end
```

### Step 5: Update Scores Controller

**File**: `app/controllers/scores_controller.rb`

Update the `heats` action to include category scores:

```ruby
def heats
  judge = Person.find(params[:judge_id])

  # Regular heat scores
  heat_scores = Score.heat_scores
    .where(judge_id: judge.id)
    .includes(heat: [:dance, entry: [:lead, :follow]])

  heats = heat_scores.map(&:heat).uniq

  # Category scores
  category_score_records = Score.category_scores
    .where(judge_id: judge.id)
    .includes(:person)

  categories_data = category_score_records.group_by(&:actual_category_id).map do |cat_id, scores|
    category = Category.find(cat_id)
    student_ids = Person.where(type: 'Student').pluck(:id)

    students_data = scores.map do |score|
      person = score.person

      # Find all heats for this student in this category
      student_heats = Heat.where(number: 1.., category: 'Closed')
        .joins(:entry, :dance)
        .where(dances: { closed_category_id: cat_id })
        .where('entries.lead_id = ? OR entries.follow_id = ?', person.id, person.id)

      {
        person_id: person.id,
        name: person.name,
        heat_count: student_heats.count,
        heat_ids: student_heats.pluck(:id).sort,
        existing_score: {
          good: score.good,
          bad: score.bad,
          value: score.value,
          comments: score.comments
        }
      }
    end

    {
      category_id: cat_id,
      category_name: category.name,
      students: students_data
    }
  end

  render json: {
    heats: heats.as_json(
      include: {
        dance: { only: [:name, :closed_category_id] },
        entry: {
          include: {
            lead: { only: [:id, :name] },
            follow: { only: [:id, :name] }
          }
        }
      },
      methods: [:category_name]
    ),
    category_scores: categories_data
  }
end

def create
  score_data = score_params

  # Check if this is a category score (negative heat_id)
  if score_data[:heat_id].to_i < 0
    # Category score
    score = Score.find_or_initialize_by(
      heat_id: score_data[:heat_id],
      judge_id: score_data[:judge_id],
      person_id: score_data[:person_id]
    )
  else
    # Regular heat score
    score = Score.find_or_initialize_by(
      heat_id: score_data[:heat_id],
      judge_id: score_data[:judge_id]
    )
  end

  score.assign_attributes(score_data)

  if score.save
    render json: { status: 'ok', score: score }
  else
    render json: { status: 'error', errors: score.errors }, status: :unprocessable_entity
  end
end

private

def score_params
  params.require(:score).permit(:heat_id, :judge_id, :person_id, :good, :bad, :value, :comments)
end
```

### Step 6: Update Judge UI

**File**: `app/views/people/_judge_section.html.erb`

Add button for new assignment type:

```erb
<div class="mt-4">
  <h3 class="font-bold text-lg mb-2">Judge Assignments</h3>

  <div class="flex gap-2 items-center flex-wrap">
    <%= button_to "Assign Judges per Heat",
        assign_judges_person_path(@person),
        method: :post,
        class: "rounded-lg py-2 px-4 bg-blue-600 text-white font-medium cursor-pointer",
        title: "Assigns judges independently for each heat, balancing across heats" %>

    <%= button_to "Assign Students by Category",
        assign_students_to_judges_by_category_person_path(@person),
        method: :post,
        class: "rounded-lg py-2 px-4 bg-green-600 text-white font-medium cursor-pointer",
        title: "Assigns each student to one judge per category, maximizing judge variety",
        disabled: Category.where(use_category_scoring: true).none? %>

    <%= button_to "Reset Assignments",
        reset_assignments_person_path(@person),
        method: :post,
        class: "rounded-lg py-2 px-4 bg-gray-400 text-white font-medium cursor-pointer",
        data: { confirm: "Clear all judge assignments?" } %>
  </div>

  <div class="mt-2 text-sm text-gray-600">
    <p><strong>Per-Heat:</strong> Each heat assigned independently (standard)</p>
    <p><strong>By Category:</strong> Each student assigned to one judge per category, with one consolidated score covering all heats in that category</p>

    <% if Category.where(use_category_scoring: true).any? %>
      <p class="mt-2"><strong>Categories enabled for category scoring:</strong></p>
      <ul class="list-disc ml-6">
        <% Category.where(use_category_scoring: true).each do |cat| %>
          <li><%= cat.name %></li>
        <% end %>
      </ul>
    <% else %>
      <p class="mt-2 text-orange-600">⚠ No categories enabled for category scoring. Enable in category settings.</p>
    <% end %>
  </div>
</div>
```

### Step 7: Implement SPA Components

**Files to create/modify**:
- `app/javascript/components/category-score.js` (new)
- `app/javascript/components/heat-page.js` (modify)
- `app/javascript/heat_data_manager.js` (modify)

See "SPA Changes" section above for detailed implementation.

### Step 8: PDF Generation Updates

**File**: `app/views/scores/_category_score_page.html.erb` (new)

Create a new partial for category score pages:

```erb
<div class="category-score-page">
  <h2><%= category.name %> - <%= student.name %></h2>

  <div class="score-details">
    <p><strong>Judge:</strong> <%= judge.name %></p>
    <p><strong>Heats covered:</strong> <%= heat_count %></p>

    <div class="score-content">
      <% if score.good %>
        <p><strong>Good:</strong> <%= score.good %>/10</p>
      <% end %>

      <% if score.comments.present? %>
        <div class="comments">
          <strong>Comments:</strong>
          <p><%= simple_format(score.comments) %></p>
        </div>
      <% end %>
    </div>
  </div>

  <div class="heat-list">
    <h3>Heats included:</h3>
    <ul>
      <% heats.each do |heat| %>
        <li>Heat <%= heat.number %> - <%= heat.dance.name %></li>
      <% end %>
    </ul>
  </div>
</div>
```

Update score publishing to handle category scores:

```ruby
# In publishing controller or helper
def generate_score_pdf(person)
  # Regular heat scores
  heat_scores = person.scores.heat_scores.includes(:heat, :judge)

  # Category scores
  category_scores = person.scores.category_scores.includes(:judge)

  pdf = Prawn::Document.new

  # ... existing heat score rendering ...

  # Render category scores (one page per category)
  category_scores.each do |score|
    category = score.actual_category
    judge = score.judge

    student_heats = Heat.where(number: 1.., category: 'Closed')
      .joins(:entry, :dance)
      .where(dances: { closed_category_id: category.id })
      .where('entries.lead_id = ? OR entries.follow_id = ?', person.id, person.id)

    pdf.start_new_page

    # Render using partial or direct PDF generation
    # ... render category score page ...
  end

  pdf.render
end
```

## Testing Strategy

### Unit Tests

**File**: `test/controllers/people_controller_test.rb`

```ruby
test "assign_students_to_judges_by_category creates balanced assignments" do
  # Setup: 3 judges, 4 categories with varying student counts
  # Execute: assign_students_to_judges_by_category
  # Assert:
  #   - Category scores created (negative heat_id)
  #   - Student pairs have same judge within category
  #   - Heat counts are balanced
  #   - Judge variety is maximized
end

test "assign_students_to_judges_by_category maximizes judge variety" do
  # Setup: Students in all categories
  # Execute: assign_students_to_judges_by_category
  # Assert: Students see all judges at least once
end
```

### JavaScript Tests

**File**: `test/javascript/category_scoring.test.js`

```javascript
import { describe, it, expect } from 'vitest';
import { HeatDataManager } from '../app/javascript/heat_data_manager.js';

describe('Category Scoring', () => {
  it('loads category scores from JSON', async () => {
    const manager = new HeatDataManager();
    // Mock fetch with category_scores data
    // Assert category scores are loaded
  });

  it('saves category score with negative heat_id', async () => {
    const manager = new HeatDataManager();
    await manager.saveCategoryScore(2, 45, { good: 8, comments: 'Great!' });

    // Assert score was posted with heat_id = -2
  });

  it('queues category scores when offline', async () => {
    // Test offline queueing for category scores
  });
});
```

### Integration Tests

Test the complete workflow from assignment to scoring to publishing.

## Documentation Updates

### CLAUDE.md

Add section documenting the heat_id convention:

```markdown
### Score Model Convention

The Score model uses the `heat_id` field to store two types of scores:

- **`heat_id > 0`**: Per-heat scoring (standard) - References a Heat record
- **`heat_id < 0`**: Per-category scoring - Represents `-category_id`

Category scores are used when `Event.student_judge_assignments` is enabled and `Category.use_category_scoring` is true. In this mode, students receive one consolidated score per category covering all their heats in that category, with feedback and comments from their assigned judge.

**Helper methods:**
- `score.category_score?` - Returns true if this is a category score
- `score.actual_category_id` - Returns the category ID (positive)
- `score.actual_category` - Returns the Category record
```

## Success Metrics

1. **Judge Variety**: Measure unique judges seen per student
   - Target: >80% for students in multiple categories

2. **Balance**: Coefficient of variation for heat distribution
   - Excellent: CV < 5%
   - Good: CV < 10%

3. **Student Satisfaction**: Consolidated feedback is clearer than per-heat comments

4. **Technical**: No performance degradation in SPA with category scoring enabled

## Future Enhancements

1. **Preview Assignment**: Show balance and variety statistics before creating scores
2. **Manual Override**: Allow reassignment of specific students to different judges
3. **Multi-day Events**: Track judge variety across multiple competition days
4. **Weighted Variety**: Allow configuring variety vs. balance priority
5. **Analytics Dashboard**: Visualize judge assignments and variety metrics
