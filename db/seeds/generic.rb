require 'yaml'

config = YAML.load(IO.read "#{__dir__}/generic.yaml")

###

Event.delete_all
Event.create!(
  name: config[:settings][:event][:name],
  location: config[:settings][:event][:location],
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
order = 0
config[:dances].to_a.map do |dance|
  order += 1
  [dance, Dance.create!(name: dance, order: order)]
end.to_h
