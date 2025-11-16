#!/usr/bin/env ruby
# Analyze per-category student-to-judge assignments with judge variety priority
# Usage: RAILS_APP_DB=event-name bin/rails runner plans/analyze_student_assignments.rb

require_relative '../config/environment'

puts "=" * 80
puts "STUDENT-TO-JUDGE ASSIGNMENT ANALYSIS (Per-Category)"
puts "=" * 80
puts

# Get judges
judges = Person.where(type: 'Judge').pluck(:id, :name)
puts "Number of judges: #{judges.count}"
judges.each do |id, name|
  puts "  - #{name} (ID: #{id})"
end
puts

if judges.count < 2
  puts "ERROR: Need at least 2 judges for assignment analysis"
  exit 1
end

# Get all students with active heats
student_ids = Person.where(type: 'Student').pluck(:id)

# Get heats grouped by category
# Heat.category is the heat type ('Open', 'Closed', etc.)
# For closed heats, we use dance.closed_category_id
heats = Heat.where(number: 1.., category: 'Closed')
  .joins(:entry, :dance)
  .where('entries.lead_id IN (?) OR entries.follow_id IN (?)', student_ids, student_ids)

# Group by category
heats_by_category = {}
heats.each do |heat|
  cat_id = heat.dance.closed_category_id
  next unless cat_id

  heats_by_category[cat_id] ||= []
  heats_by_category[cat_id] << heat
end

puts "CATEGORIES WITH STUDENT HEATS:"
puts "-" * 80

category_data = []

heats_by_category.keys.compact.sort.each do |category_id|
  category = Category.find(category_id)
  cat_heats = heats_by_category[category_id]

  # Find students and their partnerships within this category
  students_in_cat = Set.new
  student_partnerships = Hash.new { |h, k| h[k] = Set.new }
  student_heat_count = Hash.new(0)

  cat_heats.each do |heat|
    lead_id = heat.entry.lead_id
    follow_id = heat.entry.follow_id

    lead_is_student = student_ids.include?(lead_id)
    follow_is_student = student_ids.include?(follow_id)

    if lead_is_student
      students_in_cat.add(lead_id)
      student_heat_count[lead_id] += 1

      # If both are students, they must have the same judge in this category
      if follow_is_student
        student_partnerships[lead_id].add(follow_id)
        student_partnerships[follow_id].add(lead_id)
      end
    end

    if follow_is_student
      students_in_cat.add(follow_id)
      student_heat_count[follow_id] += 1
    end
  end

  puts "\nCategory: #{category.name} (ID: #{category_id})"
  puts "  Closed heats: #{cat_heats.count}"
  puts "  Unique students: #{students_in_cat.count}"

  category_data << {
    id: category_id,
    name: category.name,
    heats: cat_heats,
    students: students_in_cat.to_a,
    partnerships: student_partnerships,
    heat_count: student_heat_count
  }
end

puts
puts "=" * 80
puts "STUDENT GROUPS PER CATEGORY (must share judge within category)"
puts "=" * 80

# For each category, find connected components (student groups that must stay together)
def find_groups(partnerships, all_student_ids)
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

category_data.each do |cat|
  puts "\n#{cat[:name]}:"
  puts "-" * 80

  groups = find_groups(cat[:partnerships], cat[:students])

  groups.sort_by { |g| -g.count }.each_with_index do |group, idx|
    group_heat_count = group.sum { |sid| cat[:heat_count][sid] }

    if group.count > 1
      puts "\n  Group #{idx + 1}: #{group.count} students, #{group_heat_count} heats"
      group.each do |student_id|
        student = Person.find(student_id)
        puts "    - #{student.name} (#{cat[:heat_count][student_id]} heats)"
      end
    end
  end

  solo_students = groups.select { |g| g.count == 1 }
  if solo_students.any?
    puts "\n  Solo students (no student partners): #{solo_students.count}"
    solo_students.each do |group|
      student_id = group.first
      student = Person.find(student_id)
      puts "    - #{student.name} (#{cat[:heat_count][student_id]} heats)"
    end
  end
end

puts
puts "=" * 80
puts "ASSIGNMENT SIMULATION (Prioritizing Judge Variety)"
puts "=" * 80
puts

# Simulate assignment with judge variety priority
def simulate_assignment_with_variety(category_data, judge_count)
  # Track which judge each student gets in each category
  student_judge_history = Hash.new { |h, k| h[k] = [] }

  results = []

  category_data.each do |cat|
    # Find groups for this category
    groups = find_groups(cat[:partnerships], cat[:students])

    # Create assignment units
    units = groups.map do |group|
      {
        students: group,
        heat_count: group.sum { |sid| cat[:heat_count][sid] }
      }
    end

    # Sort by heat count descending (largest first)
    units.sort_by! { |u| -u[:heat_count] }

    # Initialize judge loads for this category
    judge_loads = (0...judge_count).map do |i|
      { student_count: 0, heat_count: 0, groups: [] }
    end

    # Greedy assignment with variety scoring
    units.each do |unit|
      # For each judge, calculate a score based on:
      # 1. Heat balance (primary)
      # 2. Judge variety for students in this unit (secondary)
      judge_scores = judge_loads.each_with_index.map do |load, judge_idx|
        # Heat balance component (lower heat count is better)
        heat_score = load[:heat_count]

        # Judge variety component (how many students in this unit have seen this judge)
        repeat_count = unit[:students].count { |sid| student_judge_history[sid].include?(judge_idx) }
        variety_penalty = repeat_count * 1000  # Make variety a strong factor

        total_score = heat_score + variety_penalty

        [judge_idx, total_score]
      end

      # Assign to judge with minimum score
      min_judge_idx = judge_scores.min_by { |idx, score| score }.first

      judge_loads[min_judge_idx][:student_count] += unit[:students].count
      judge_loads[min_judge_idx][:heat_count] += unit[:heat_count]
      judge_loads[min_judge_idx][:groups] << unit

      # Update student history
      unit[:students].each do |student_id|
        student_judge_history[student_id] << min_judge_idx
      end
    end

    results << {
      category: cat[:name],
      category_id: cat[:id],
      judge_loads: judge_loads
    }
  end

  [results, student_judge_history]
end

results, student_judge_history = simulate_assignment_with_variety(category_data, judges.count)

results.each do |result|
  puts "\n#{result[:category]} (ID: #{result[:category_id]}):"
  puts "-" * 40

  result[:judge_loads].each_with_index do |load, idx|
    puts "  Judge #{idx + 1} (#{judges[idx][1]}):"
    puts "    Students: #{load[:student_count]}"
    puts "    Heats: #{load[:heat_count]}"
  end

  # Balance statistics
  student_counts = result[:judge_loads].map { |l| l[:student_count] }
  heat_counts = result[:judge_loads].map { |l| l[:heat_count] }

  puts "  Balance:"
  puts "    Student range: #{student_counts.min}-#{student_counts.max} (diff: #{student_counts.max - student_counts.min})"
  puts "    Heat range: #{heat_counts.min}-#{heat_counts.max} (diff: #{heat_counts.max - heat_counts.min})"
end

puts
puts "=" * 80
puts "JUDGE VARIETY ANALYSIS"
puts "=" * 80
puts

# Analyze judge variety across categories
all_students = student_judge_history.keys.sort
students_by_category_count = all_students.group_by { |sid| student_judge_history[sid].count }

puts "\nStudents by number of categories enrolled:"
students_by_category_count.keys.sort.reverse.each do |cat_count|
  students = students_by_category_count[cat_count]
  puts "  #{cat_count} categories: #{students.count} students"
end

# Students in all categories
if students_by_category_count[category_data.count]
  puts "\nStudents in all #{category_data.count} categories:"
  students_by_category_count[category_data.count].each do |student_id|
    student = Person.find(student_id)
    judge_assignments = student_judge_history[student_id]
    unique_judges = judge_assignments.uniq.count
    judge_names = judge_assignments.map { |j_idx| judges[j_idx][1] }.join(", ")

    puts "  - #{student.name}: #{unique_judges} unique judges (#{judge_names})"
  end
end

# Overall variety metrics
puts "\nOverall Variety Metrics:"
total_assignments = student_judge_history.values.flatten.count
unique_assignments = student_judge_history.values.map { |assignments| assignments.uniq.count }.sum
puts "  Total category assignments: #{total_assignments}"
puts "  Unique judge exposures: #{unique_assignments}"
puts "  Variety ratio: #{'%.1f' % (unique_assignments.to_f / total_assignments * 100)}%"
puts "  (100% = every student sees different judge in every category)"

puts
puts "=" * 80
puts "OVERALL WORKLOAD BALANCE"
puts "=" * 80
puts

# Calculate total workload per judge across all categories
total_judge_loads = judges.count.times.map { { student_assignments: 0, heat_count: 0 } }

results.each do |result|
  result[:judge_loads].each_with_index do |load, idx|
    total_judge_loads[idx][:student_assignments] += load[:student_count]
    total_judge_loads[idx][:heat_count] += load[:heat_count]
  end
end

total_judge_loads.each_with_index do |load, idx|
  puts "Judge #{idx + 1} (#{judges[idx][1]}):"
  puts "  Total student assignments: #{load[:student_assignments]}"
  puts "  Total heats: #{load[:heat_count]}"
end

puts
student_assignment_counts = total_judge_loads.map { |l| l[:student_assignments] }
heat_counts = total_judge_loads.map { |l| l[:heat_count] }

puts "Balance Statistics:"
puts "  Student assignments: #{student_assignment_counts.min}-#{student_assignment_counts.max} (diff: #{student_assignment_counts.max - student_assignment_counts.min})"
puts "  Heats: #{heat_counts.min}-#{heat_counts.max} (diff: #{heat_counts.max - heat_counts.min})"
puts "  Average student assignments per judge: #{'%.1f' % (student_assignment_counts.sum.to_f / judges.count)}"
puts "  Average heats per judge: #{'%.1f' % (heat_counts.sum.to_f / judges.count)}"

# Calculate coefficient of variation
def coefficient_of_variation(values)
  mean = values.sum.to_f / values.count
  variance = values.sum { |v| (v - mean) ** 2 } / values.count
  std_dev = Math.sqrt(variance)
  (std_dev / mean * 100).round(1)
end

puts "  Heat distribution CV: #{coefficient_of_variation(heat_counts)}% (lower is better)"

puts
if heat_counts.max - heat_counts.min <= heat_counts.sum / judges.count * 0.3
  puts "✓ Assignment is WELL BALANCED - difference is within 30% of average"
elsif heat_counts.max - heat_counts.min <= heat_counts.sum / judges.count * 0.5
  puts "⚠ Assignment is MODERATELY BALANCED - some variance exists"
else
  puts "✗ Assignment is POORLY BALANCED - significant variance"
end

puts
puts "=" * 80
puts "FEASIBILITY ASSESSMENT"
puts "=" * 80
puts

feasible = true
issues = []

# Check if judge variety is achievable
category_count = category_data.count
if category_count > judges.count
  max_unique = judges.count
  puts "✓ Judge variety: #{category_count} categories with #{judges.count} judges"
  puts "  Students in all categories will see all #{judges.count} judges at least once"
  puts "  Some judge repeats are inevitable but variety is maximized"
elsif category_count == judges.count
  puts "✓ Judge variety: Perfect alignment (#{category_count} categories, #{judges.count} judges)"
  puts "  Students in all categories can see every judge exactly once"
else
  puts "✓ Judge variety: More judges than categories (#{judges.count} judges, #{category_count} categories)"
  puts "  Students in all categories can see different judges"
end

# Check balance
if heat_counts.max - heat_counts.min > heat_counts.sum / judges.count * 0.5
  feasible = false
  issues << "Workload imbalance exceeds 50% of average"
end

puts
if feasible
  puts "✓ REQUIREMENTS ARE FEASIBLE"
  puts "  - Judge assignments can be balanced"
  puts "  - Judge variety can be maximized within constraints"
  puts "  - Student partnerships will be preserved within each category"
else
  puts "✗ REQUIREMENTS MAY NEED ADJUSTMENT"
  issues.each { |issue| puts "  - #{issue}" }
end
