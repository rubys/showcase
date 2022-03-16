if ENV['SHOWCASE'] == 'Raleigh'
  # require_relative 'seeds/raleigh.rb'
elsif ENV['SHOWCASE'] == 'Harrisburg'
  require_relative 'seeds/harrisburg.rb'
else
  require_relative 'seeds/generic.rb'
end
