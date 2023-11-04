#!usr/bin/evn ruby
require 'json'
require 'tomlrb'

primary_region = Tomlrb.parse(IO.read 'fly.toml')['primary_region']

pending = JSON.parse(IO.read(DEPLOYED))['pending'] || {}

if pending['add'] and not pending['add'].empty?
  machines = JSON.parse(`fly machines list --json`)
  primary = machines.find {|machine| machine['region'] == primary_region}
end

(pending['add'] || []).each do |region|
  exit 1 unless system "fly machine clone #{primary} --region #{region}"
end

if File.exist? 'db/map.yml'
  new_map = IO.read('db/map.yml')
  if new_map != IO.read('config/tenant/map.yml')
    IO.write('config/tenant/map.yml', new_map)

    exit 1 unless system 'node utils/mapper/usmap.js'
  end
end

if File.exist? 'db/showcases.yml'
  new_map = IO.read('db/showcases.yml')
  if new_map != IO.read('config/tenant/showcases.yml')
    IO.write('config/tenant/showcases.yml', new_map)
  end
end

exit 1 unless system "fly deploy"

(pending['delete'] || []).each do |region|
  machine = machines.find {|machine| machine['region'] == primary_region}
  exit 1 unless system "fly machine destroy --force #{primary} --region #{region}"
end