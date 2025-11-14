#!/usr/bin/env ruby
# Analyze student partnerships and judge assignment feasibility

require_relative 'config/environment'

puts "=" * 80
puts "STUDENT-TO-JUDGE ASSIGNMENT ANALYSIS"
puts "=" * 80
puts

# Get judges
judges = Person.where(type: 'Judge').pluck(:id, :name)
puts "Number of judges: #{judges.count}"
judges.each do |id, name|
  puts "  - #{name} (ID: #{id})"
end
puts

# Get all students with active heats
students = Person.where(type: 'Student').includes(
  lead_entries: [:follow, :heats],
  follow_entries: [:lead, :heats]
)

# Build student partnership graph
student_partnerships = Hash.new { |h, k| h[k] = Set.new }
student_heats = Hash.new(0)

students.each do |student|
  heat_count = 0

  # Check lead entries
  student.lead_entries.each do |entry|
    active_heats = entry.heats.select { |h| h.number >= 1 }
    heat_count += active_heats.count

    # If follow is also a student, they're partners
    if entry.follow.type == 'Student'
      student_partnerships[student.id].add(entry.follow.id)
      student_partnerships[entry.follow.id].add(student.id)
    end
  end

  # Check follow entries
  student.follow_entries.each do |entry|
    active_heats = entry.heats.select { |h| h.number >= 1 }
    heat_count += active_heats.count

    # If lead is also a student, they're partners
    if entry.lead.type == 'Student'
      student_partnerships[student.id].add(entry.lead.id)
      student_partnerships[entry.lead.id].add(student.id)
    end
  end

  student_heats[student.id] = heat_count if heat_count > 0
end

puts "Total students with heats: #{student_heats.count}"
puts "Total heats involving students: #{student_heats.values.sum}"
puts

# Find connected components (student groups that must stay together)
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

  # Add solo students (those with no student partners)
  all_student_ids.each do |student_id|
    unless visited.include?(student_id)
      groups << [student_id]
    end
  end

  groups
end

groups = find_groups(student_partnerships, student_heats.keys)

puts "STUDENT GROUPS (must be assigned to same judge):"
puts "-" * 80

groups.sort_by { |g| -g.count }.each_with_index do |group, idx|
  group_heat_count = group.sum { |sid| student_heats[sid] }

  if group.count > 1
    puts "\nGroup #{idx + 1}: #{group.count} students, #{group_heat_count} total heats"
    group.each do |student_id|
      student = Person.find(student_id)
      puts "  - #{student.name} (#{student_heats[student_id]} heats)"
    end
  end
end

solo_students = groups.select { |g| g.count == 1 }
puts "\nSolo students (no student partners): #{solo_students.count}"
solo_students.each do |group|
  student_id = group.first
  student = Person.find(student_id)
  puts "  - #{student.name} (#{student_heats[student_id]} heats)"
end

puts
puts "=" * 80
puts "ASSIGNMENT BALANCE SIMULATION"
puts "=" * 80
puts

# Simulate greedy assignment
def simulate_assignment(groups, student_heats, judge_count)
  # Create assignment units
  units = groups.map do |group|
    {
      students: group,
      heat_count: group.sum { |sid| student_heats[sid] }
    }
  end

  # Sort by heat count descending (largest first)
  units.sort_by! { |u| -u[:heat_count] }

  # Initialize judge loads
  judge_loads = (1..judge_count).map do |i|
    { student_count: 0, heat_count: 0, groups: [] }
  end

  # Greedy assignment
  units.each do |unit|
    # Find judge with minimum load (prioritize heat balance)
    min_judge_idx = judge_loads.each_with_index.min_by do |load, idx|
      load[:heat_count]
    end[1]

    judge_loads[min_judge_idx][:student_count] += unit[:students].count
    judge_loads[min_judge_idx][:heat_count] += unit[:heat_count]
    judge_loads[min_judge_idx][:groups] << unit
  end

  judge_loads
end

judge_loads = simulate_assignment(groups, student_heats, judges.count)

judge_loads.each_with_index do |load, idx|
  puts "Judge #{idx + 1} (#{judges[idx][1]}):"
  puts "  Students: #{load[:student_count]}"
  puts "  Heats: #{load[:heat_count]}"
  puts "  Groups: #{load[:groups].count}"
end

puts
puts "Balance Statistics:"
student_counts = judge_loads.map { |l| l[:student_count] }
heat_counts = judge_loads.map { |l| l[:heat_count] }

puts "  Student assignment range: #{student_counts.min} - #{student_counts.max} (diff: #{student_counts.max - student_counts.min})"
puts "  Heat assignment range: #{heat_counts.min} - #{heat_counts.max} (diff: #{heat_counts.max - heat_counts.min})"
puts "  Average students per judge: #{'%.1f' % (student_counts.sum.to_f / judges.count)}"
puts "  Average heats per judge: #{'%.1f' % (heat_counts.sum.to_f / judges.count)}"

# Calculate coefficient of variation (std dev / mean) - lower is better balance
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
