if ENV['SHOWCASE'] == 'Raleigh'
  # require_relative 'seeds/raleigh.rb'
else
  require_relative 'seeds/harrisburg.rb'
end
