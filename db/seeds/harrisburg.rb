# Argentine vs Arg. Tango

require 'csv'
require 'pp'
require 'set'
require 'yaml'

source = '/Users/rubys/Documents/Showcase 2022 Direct'

config = YAML.load(IO.read "#{__dir__}/harrisburg.yaml")

listing = IO.read(Dir["#{source}/Initial Listing*.csv"].first)
listing = CSV.parse(listing.gsub("\r", ""))
listing.shift

studios = Set.new
people = {}
dances = Set.new(config[:dances])
entries = []

lead = nil
follow = nil
level = nil
age = nil

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

    age = entry[8]
    
    unless name.include? '&'
      people[name] ||= {
       studio: entry[1],
       name: name,
       type: 'Student',
       age: [],
       level: [],
       role: role
      }

      people[name][:age] << age
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
      follow: follow,
      level: level,
      age: age
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

  people[name][:role] ||= 'Follower'
end

###

Event.delete_all
Event.create!(
  name: config[:settings][:event][:name],
  location: config[:settings][:event][:location],
  date: config[:settings][:event][:date],
  heat_range_cat: config[:settings][:heat][:category],
  heat_range_level: config[:settings][:heat][:level],
  heat_range_age: config[:settings][:heat][:age],
)

Age.delete_all
ages = config[:ages].map do |category, description|
  [category, Age.create!(category: category, description: description)]
end.to_h

Level.delete_all
levels = config[:levels].map do |name|
  [name, Level.create!(name: name)]
end.to_h

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
  unless name.include? ','
    parts = name.split(' ').rotate(-1)
    parts[0] += ','
    person[:name] = parts.join(' ')
  end

  if person[:age]
    person[:age] = ages[person.delete(:age).max]
  end

  if person[:level]
    person[:level] = levels[person[:level]]
  end

  person[:studio] = studios[person[:studio]]
  [name, Person.create!(person)]
end.to_h

ActiveRecord::Base.transaction do
Entry.delete_all
Heat.delete_all

entries = entries.group_by {|entry|
  [entry[:lead], entry[:follow], entry[:age], entry[:level]]
}

entries = entries.map do |(lead, follow, age, level), heats|
  entry = {
    lead: people[lead],
    follow: people[follow],
    age: ages[age],
    level: levels[level]
  }

  entry = Entry.create! entry

  heats.each do |heat|
    Heat.create!({
      number: 0,
      entry: entry,
      category: heat[:category],
      dance: dances[heat[:dance]]
    })
  end
end
end
