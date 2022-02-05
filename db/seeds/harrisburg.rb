# Argentine vs Arg. Tango

require 'csv'
require 'pp'
require 'set'
require 'yaml'

source = '/Users/rubys/Documents/Showcase 2022 Direct'

listing = IO.read(Dir["#{source}/Initial Listing*.csv"].first)
listing = CSV.parse(listing.gsub("\r", ""))
listing.shift

studios = Set.new
people = {}
dances = Set.new(YAML.load(IO.read "#{__dir__}/harrisburg.yaml")[:dances])
entries = []

lead = nil
follow = nil
listing.each do |entry|
  if entry[0]
    name = entry[0]
    
    if entry[10] == name
      role = 'Follower'
    else
      role = 'Leader'
    end
    
    case entry[2]
      when 'BA'
        level = 'Assoc. Bronze'
      when 'BF'
        level = 'Full Bronze'
      when 'SA'
        level = 'Assoc. Silver'
      when 'SF'
        level = 'Full Silver'
      when 'GA'
        level = 'Assoc. Gold'
      when 'GF'
        level = 'Full Gold'
      else
        level = 'Newcomer'
    end
    
    unless name.include? '&'
      people[name] ||= {
       studio: entry[1],
       name: name,
       type: 'Student',
       age: [],
       level: [],
       role: role
      }

      people[name][:age] << entry[8]
      people[name][:level] << level
    end

    people[entry[6]] ||= {
      studio: entry[1],
      name: entry[6],
      type: 'Professional',
    }

    studios << entry[1]

    follow = entry[10]
    lead = entry[11]
  end

  if entry[5]
    dance = entry[5]
    dance = 'Arg. Tango' if dance == 'Argentine'

    dances << dance

    entries << {
      category: entry[9] == 'O' ? 'Open' : 'Closed',
      count: 1,
      dance: dance,
      lead: lead,
      follow: follow
    }
  end
end

###

people.each do |name, person|
  level = person.delete(:level)
  next unless level
  level = level.to_a.compact.uniq

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


leaders = entries.map {|entry| entry[:lead]}.uniq
followers = entries.map {|entry| entry[:follow]}.uniq

leaders.each do |name|
  unless people[name]
    entry = entries.find {|entry| entry[:lead] == name}

    people[name] ||= {
      studio: people[entry[:follow]][:studio],
      name: name,
      type: 'Professional',
    }
  end

  people[name][:role] ||= (followers.include?(name) ? 'Both' : 'Leader')
end

followers.each do |name|
  unless people[name]
    entry = entries.find {|entry| entry[:follow] == name}

    people[name] ||= {
      studio: people[entry[:lead]][:studio],
      name: name,
      type: 'Professional',
    }
  end

  people[name][:role] ||= 'Follow'
end

###

Dance.delete_all
dances = dances.to_a.map do |dance|
  [dance, Dance.create!(name: dance)]
end.to_h

Studio.delete_all
studios = studios.to_a.sort.map do |name|
  [name, Studio.create!(name: name, tables: 0)]
end.to_h

Person.delete_all
people = people.map do |name, person|
  if person[:age]
    person[:category] = person.delete(:age).max
  end

  person[:studio] = studios[person[:studio]]
  [name, Person.create!(person)]
end.to_h

Entry.delete_all
entries = entries.map do |entry|
  heats = entry.delete :heats
  entry[:dance] = dances[entry[:dance]]
  entry[:lead] = people[entry[:lead]]
  entry[:follow] = people[entry[:follow]]
  entry = Entry.create! entry

  (entry[:count]..1).each do |heat|
    Heat.create!({number: heat, entry: entry})
  end
end
