#!/usr/bin/env ruby

require 'sqlite3'
require_relative '../config/environment'

# Get database path from command line or use default
database_path = ARGV[0] || 'db/2025-torino-april.sqlite3'

# Ensure we're in the Rails root directory
Dir.chdir(File.expand_path('..', __dir__))

# Connect to database
db = SQLite3::Database.new(database_path)
db.results_as_hash = true

# Get the table size from the event
table_size = db.get_first_value("SELECT table_size FROM events LIMIT 1") || 10

# Get all billable options (meal options)
options = db.execute("SELECT * FROM billables WHERE type = 'Option' ORDER BY name")

# Large studios we're tracking
large_studios = ['Event Staff', 'NY-Broadway', 'Lincolnshire', 'Columbia', 'Waco', 'Bucharest', 'Greenwich']

# Get studio pairs
studio_pairs = db.execute(<<~SQL)
  SELECT s1.name as studio1_name, s2.name as studio2_name
  FROM studio_pairs sp
  JOIN studios s1 ON sp.studio1_id = s1.id
  JOIN studios s2 ON sp.studio2_id = s2.id
SQL

def manhattan_distance(pos1, pos2)
  (pos1[:row] - pos2[:row]).abs + (pos1[:col] - pos2[:col]).abs
end

def contiguous_block?(positions)
  return true if positions.size <= 1
  
  # Check if all positions form a contiguous block
  rows = positions.map { |p| p[:row] }.uniq.sort
  cols = positions.map { |p| p[:col] }.uniq.sort
  
  # Check if they form a horizontal line (same row, consecutive columns)
  if rows.size == 1 && cols.each_cons(2).all? { |a, b| b - a == 1 }
    return true
  end
  
  # Check if they form a vertical line (same column, consecutive rows)
  if cols.size == 1 && rows.each_cons(2).all? { |a, b| b - a == 1 }
    return true
  end
  
  # Check if they form a rectangular block
  if rows.size <= 2 && cols.size <= 4
    # Check if all expected positions in the rectangle are filled
    expected_positions = rows.product(cols).map { |r, c| {row: r, col: c} }
    expected_positions.all? { |expected| positions.include?(expected) }
  else
    false
  end
end

def analyze_studio_adjacency(db, option_id, studio_name)
  # Get all tables for this studio in this option
  tables = db.execute(<<~SQL, [option_id, studio_name])
    SELECT DISTINCT t.id, t.number, t.row, t.col
    FROM tables t
    JOIN person_options po ON t.id = po.table_id
    JOIN people p ON po.person_id = p.id
    JOIN studios s ON p.studio_id = s.id
    WHERE t.option_id = ? AND s.name = ?
    ORDER BY t.number
  SQL
  
  return { success: true, reason: 'No tables' } if tables.empty?
  return { success: true, reason: 'Single table' } if tables.size == 1
  
  # Extract positions
  positions = tables.map { |t| { row: t['row'], col: t['col'] } }
  
  # Check if it's a contiguous block
  if contiguous_block?(positions)
    return { success: true, reason: 'Contiguous block' }
  end
  
  # Check traditional adjacency (distance 1 between consecutive tables)
  adjacent_count = 0
  total_pairs = tables.size - 1
  
  tables.each_cons(2) do |table1, table2|
    pos1 = { row: table1['row'], col: table1['col'] }
    pos2 = { row: table2['row'], col: table2['col'] }
    distance = manhattan_distance(pos1, pos2)
    adjacent_count += 1 if distance == 1
  end
  
  if adjacent_count == total_pairs
    { success: true, reason: 'All adjacent' }
  else
    # Calculate distances for failure analysis
    distances = []
    tables.each_cons(2) do |table1, table2|
      pos1 = { row: table1['row'], col: table1['col'] }
      pos2 = { row: table2['row'], col: table2['col'] }
      distances << manhattan_distance(pos1, pos2)
    end
    
    { 
      success: false, 
      reason: "#{adjacent_count}/#{total_pairs} adjacent", 
      distances: distances,
      tables: tables.map { |t| "#{t['number']}(#{t['row']},#{t['col']})" }
    }
  end
end

def analyze_studio_pair_success(db, option_id, studio1_name, studio2_name)
  # Check if studios share any tables
  shared_tables = db.execute(<<~SQL, [option_id, studio1_name, studio2_name])
    SELECT t.id, t.number, t.row, t.col
    FROM tables t
    JOIN person_options po ON t.id = po.table_id
    JOIN people p ON po.person_id = p.id
    JOIN studios s ON p.studio_id = s.id
    WHERE t.option_id = ? AND s.name IN (?, ?)
    GROUP BY t.id
    HAVING COUNT(DISTINCT s.name) = 2
    ORDER BY t.number
  SQL
  
  if shared_tables.any?
    return { success: true, reason: 'Shared table(s)', shared_count: shared_tables.size }
  end
  
  # If no shared tables, check if their separate tables are adjacent
  studio1_tables = db.execute(<<~SQL, [option_id, studio1_name])
    SELECT DISTINCT t.id, t.number, t.row, t.col
    FROM tables t
    JOIN person_options po ON t.id = po.table_id
    JOIN people p ON po.person_id = p.id
    JOIN studios s ON p.studio_id = s.id
    WHERE t.option_id = ? AND s.name = ?
    ORDER BY t.number
  SQL
  
  studio2_tables = db.execute(<<~SQL, [option_id, studio2_name])
    SELECT DISTINCT t.id, t.number, t.row, t.col
    FROM tables t
    JOIN person_options po ON t.id = po.table_id
    JOIN people p ON po.person_id = p.id
    JOIN studios s ON p.studio_id = s.id
    WHERE t.option_id = ? AND s.name = ?
    ORDER BY t.number
  SQL
  
  return { success: true, reason: 'No tables for pairing' } if studio1_tables.empty? || studio2_tables.empty?
  
  # Check if any tables from studio1 are adjacent to any tables from studio2
  min_distance = Float::INFINITY
  closest_pair = nil
  
  studio1_tables.each do |t1|
    studio2_tables.each do |t2|
      pos1 = { row: t1['row'], col: t1['col'] }
      pos2 = { row: t2['row'], col: t2['col'] }
      distance = manhattan_distance(pos1, pos2)
      
      if distance < min_distance
        min_distance = distance
        closest_pair = [t1, t2]
      end
    end
  end
  
  if min_distance == 1
    { success: true, reason: 'Adjacent tables' }
  else
    { 
      success: false, 
      reason: "Min distance: #{min_distance}", 
      closest_pair: closest_pair.map { |t| "#{t['number']}(#{t['row']},#{t['col']})" }
    }
  end
end

puts "=" * 80
puts "ADJACENCY ANALYSIS (Table Size: #{table_size})"
puts "=" * 80
puts "Database: #{database_path}"

# Track overall statistics
large_studio_results = {}
pair_results = {}

options.each do |option|
  puts "\n#{option['name']}:"
  puts "-" * 40
  
  # Analyze large studios
  large_studios.each do |studio_name|
    result = analyze_studio_adjacency(db, option['id'], studio_name)
    large_studio_results[studio_name] ||= { success: 0, total: 0 }
    large_studio_results[studio_name][:total] += 1
    large_studio_results[studio_name][:success] += 1 if result[:success]
    
    status = result[:success] ? "✓" : "✗"
    puts "  #{status} #{studio_name}: #{result[:reason]}"
    
    unless result[:success]
      puts "      Tables: #{result[:tables].join(', ')}" if result[:tables]
      puts "      Distances: #{result[:distances].join(', ')}" if result[:distances]
    end
  end
  
  # Analyze studio pairs
  studio_pairs.each do |pair|
    studio1, studio2 = pair['studio1_name'], pair['studio2_name']
    result = analyze_studio_pair_success(db, option['id'], studio1, studio2)
    
    pair_key = "#{studio1} ↔ #{studio2}"
    pair_results[pair_key] ||= { success: 0, total: 0 }
    pair_results[pair_key][:total] += 1
    pair_results[pair_key][:success] += 1 if result[:success]
    
    status = result[:success] ? "✓" : "✗"
    puts "  #{status} #{pair_key}: #{result[:reason]}"
    
    unless result[:success]
      puts "      Closest: #{result[:closest_pair].join(' to ')}" if result[:closest_pair]
    end
  end
end

puts "\n" + "=" * 80
puts "OVERALL SUMMARY"
puts "=" * 80

puts "\nLarge Studios:"
large_studio_results.each do |studio, stats|
  percentage = (stats[:success] * 100.0 / stats[:total]).round(1)
  puts "  #{studio}: #{stats[:success]}/#{stats[:total]} (#{percentage}%)"
end

puts "\nStudio Pairs:"
pair_results.each do |pair, stats|
  percentage = (stats[:success] * 100.0 / stats[:total]).round(1)
  puts "  #{pair}: #{stats[:success]}/#{stats[:total]} (#{percentage}%)"
end

# Calculate overall success rates
total_large_success = large_studio_results.values.sum { |s| s[:success] }
total_large_attempts = large_studio_results.values.sum { |s| s[:total] }
large_success_rate = (total_large_success * 100.0 / total_large_attempts).round(1)

total_pair_success = pair_results.values.sum { |s| s[:success] }
total_pair_attempts = pair_results.values.sum { |s| s[:total] }
pair_success_rate = (total_pair_success * 100.0 / total_pair_attempts).round(1)

puts "\n" + "=" * 80
puts "FINAL RESULTS"
puts "=" * 80
puts "Large Studios: #{total_large_success}/#{total_large_attempts} (#{large_success_rate}%)"
puts "Studio Pairs: #{total_pair_success}/#{total_pair_attempts} (#{pair_success_rate}%)"
puts "Overall Success: #{total_large_success + total_pair_success}/#{total_large_attempts + total_pair_attempts} (#{((total_large_success + total_pair_success) * 100.0 / (total_large_attempts + total_pair_attempts)).round(1)}%)"

# Additional verification: Check Event Staff separation
puts "\n" + "=" * 80
puts "EVENT STAFF SEPARATION VERIFICATION"
puts "=" * 80

options.each do |option|
  mixed_tables = db.execute(<<~SQL, option['id'])
    SELECT t.number, 
           COUNT(DISTINCT CASE WHEN p.studio_id = 0 THEN 1 END) as event_staff_count,
           COUNT(DISTINCT CASE WHEN p.studio_id != 0 THEN 1 END) as other_studio_count
    FROM tables t
    JOIN person_options po ON t.id = po.table_id
    JOIN people p ON po.person_id = p.id
    WHERE t.option_id = ?
    GROUP BY t.id, t.number
    HAVING event_staff_count > 0 AND other_studio_count > 0
  SQL
  
  if mixed_tables.any?
    puts "❌ #{option['name']}: Event Staff mixed with other studios at tables #{mixed_tables.map{|t| t['number']}.join(', ')}"
  else
    puts "✅ #{option['name']}: Event Staff properly separated"
  end
end