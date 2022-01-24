#
# Period instead of a comma in Partipants page:
#   Howard. Jennifer
#
# Three followers with a number assigned:
#   DeBerardinis, Margo
#   Howard. Jennifer
#   Kipps, Ashley
#
# Leading space in name on Total Entries page:
#   Ryan Caine
#

require 'csv'
require 'pp'
require 'set'

source = '/Users/rubys/Documents/The Greatest Show 2022'

participants = IO.read(Dir["#{source}/Participants*.csv"].first)
participants = CSV.parse(participants.gsub("\r", ""))
participants.shift

studios = []
people = {}
dances = Set.new

participants.each do |participant|
  if participant[0]
    studios << participant[0]
  else
    person = {
      studio: participant[5],
      type: participant[3],
      name: participant[2]
   }
    person[:back] = participant[1] if participant[1]

    case participant[3]
      when 'P' then person[:type] = 'Professional'
      when 'S' then person[:type] = 'Student'
      when 'G' then person[:type] = 'Guest'
      when 'J'
        person[:type] = 'Judge'
        person.delete :studio
      when 'MC'
        person[:type] = 'Emcee'
        person.delete :studio
    end

    case participant[4]
      when 'L' then person[:role] = 'Leader'
      when 'L/F' then person[:role] = 'Both'
      when 'F'
        if person[:back]
          STDERR.puts "follower with a number assigned: #{person[:name]}"
        end
        person[:role] = person[:back] ? 'Both' : 'Follower'
    end

    unless studios.include? participant[5]
      STDERR.puts "studio not found:"
      STDERR.puts participant.inspect
      exit
    end

    person[:friday_dinner] = true if participant[6] == 'TRUE'
    person[:saturday_lunch] = true if participant[7] == 'TRUE'
    person[:saturday_dinner] = true if participant[8] == 'TRUE'

    name = person[:name].split(/[,.]\s*/).rotate.join(' ')
    
    people[name] = person
  end
end

entries = IO.read(Dir["#{source}/Total Entries-*.csv"].first)
entries = CSV.parse(entries.gsub("\r", ""))
entries.shift

entries.each do |entry|
  dances.add entry[2]

  lead = people[entry[4].strip]
  follow = people[entry[5].strip]

  if lead
    unless %w(Leader Both).include? lead[:role]
      STDERR.puts "#{entry[4]} is a leader with role #{lead[:role]}"
    end

    unless lead[:type] == 'Professional'
      lead[:entry_level] ||= Set.new
      lead[:entry_level].add entry[6]

      if entry[7]
        lead[:entry_cat] ||= Set.new
        lead[:entry_cat].add entry[7].split(' ').last
      end

      if entry[9] and entry[9] != entry[5]
        lead[:credit] ||= Set.new
        lead[:credit].add entry[9].strip
      end
    end
  else
    STDERR.puts "entry missing person: #{entry[4].inspect}"
  end

  if follow
    unless %w(Follower Both).include? follow[:role]
      STDERR.puts "#{entry[5]} is a follower with role #{follow[:role]}"
    end

    unless follow[:type] == 'Professional'
      follow[:entry_level] ||= Set.new
      follow[:entry_level].add entry[6]

      if entry[7]
        follow[:entry_cat] ||= Set.new
        follow[:entry_cat].add entry[7].split(' ').last
      end

      if entry[9] and entry[9] != entry[4]
        follow[:credit] ||= Set.new
        follow[:credit].add entry[9].strip
      end
    end
  else
    STDERR.puts "entry missing person: #{entry[5].inspect}"
  end
end

people.each do |name, person|
  level = person.delete(:entry_level)
  next unless level
  level = level.to_a.compact

  if level.size > 1
    STDERR.puts "#{name} has multiple levels on the entry page:"
    STDERR.puts '  ' + level.to_a.inspect
   
    gold = level.select {|level| level.include? 'Gold'}
    silver = level.select {|level| level.include? 'Silver'}
    full = level.select {|level| level.include? 'Full'}

    level = full if full.size == 1
    level = silver if silver.size == 1
    level = gold if gold.size == 1
  end

  person[:level] = level.first
end

people.each do |name, person|
  entry_cat = person.delete(:entry_cat)
  next unless entry_cat
  if entry_cat.size > 1
    STDERR.puts "#{name} has multiple categories on the entry page:"
    STDERR.puts '  ' + entry_cat.to_a.inspect
  end
  person[:category] = entry_cat.to_a.max
end

people.each do |name, person|
  credit = person.delete(:credit)
  next unless credit and credit.size > 1
  STDERR.puts "#{name} has multiple credits on the entry page:"
  STDERR.puts '  ' + credit.to_a.inspect
end

heats = IO.read(Dir["#{source}/Heats*.csv"].first)
heats = CSV.parse(heats.gsub("\r", ""))
heats.shift

entries = []

heats.each do |heat|
  next unless heat[0] and heat[5]
  unless dances.include? heat[2]
    STDERR.puts "Unknown dance: #{heat[2]}"
  end
  unless people.include? heat[4]
    STDERR.puts "Unknown person: #{heat.inspect}"
  end
  unless people.include? heat[5]
    STDERR.puts "Unknown person: #{heat.inspect}"
  end

  entries << {
    category: heat[1],
    dance: heat[2],
    lead: heat[4],
    follow: heat[5],
  }
end

entries = entries.group_by {|entry| entry}.map do |entry, list|
  {count: list.size}.merge(entry)
end

###

Dance.delete_all
dances = dances.to_a.sort.map do |dance|
  [dance, Dance.create!(name: dance)]
end.to_h

Studio.delete_all
studios = studios.sort.map do |studio|
  [studio, Studio.create!(name: studio)]
end.to_h

Person.delete_all
people = people.map do |name, person|
  person[:studio] = studios[person[:studio]]
  [name, Person.create!(person)]
end.to_h

Entry.delete_all
entries = entries.map do |entry|
  entry[:dance] = dances[entry[:dance]]
  entry[:lead] = people[entry[:lead]]
  entry[:follow] = people[entry[:follow]]
  Entry.create! entry
end
