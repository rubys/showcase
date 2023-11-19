#!/usr/bin/env ruby
require 'json'
require 'tomlrb'

fly = File.join(Dir.home, '.fly/bin/flyctl')

primary_region = Tomlrb.parse(IO.read 'fly.toml')['primary_region']

pending = JSON.parse(IO.read('tmp/deployed.json'))['pending'] || {}

if pending['add'] and not pending['add'].empty?
  machines = JSON.parse(`#{fly} machines list --json`)
  primary = machines.find {|machine| machine['region'] == primary_region}
end

(pending['add'] || []).each do |region|
  cmd = [fly, 'machine', 'clone', primary['id'], '--region', region, '--verbose']

  volumes = JSON.parse(`fly volumes list --json`)
  volume = volumes.find do |volume| 
    volume['region'] == region && volume['attached_machine_id'] == nil
  end
  cmd += ['--attach-volume', volume['id']] if volume

  exit 1 unless system *cmd
end

if File.exist? 'db/map.yml'
  exit 1 unless system 'node utils/mapper/usmap.js'

  new_map = IO.read('db/map.yml')
  if new_map != IO.read('config/tenant/map.yml')
    IO.write('config/tenant/map.yml', new_map)
  end
end

if File.exist? 'db/showcases.yml'
  new_map = IO.read('db/showcases.yml')
  if new_map != IO.read('config/tenant/showcases.yml')
    IO.write('config/tenant/showcases.yml', new_map)
  end
end

unless `git status --short | grep -v "^?? "`.empty?
  exit 1 unless system "#{fly} deploy"
end

(pending['delete'] || []).each do |region|
  machines = JSON.parse(`#{fly} machines list --json`)
  machine = machines.find {|machine| machine['region'] == region}
  exit 1 unless system "#{fly} machine destroy --force #{machine['id']} --verbose" if machine
end

unless `git status --short | grep -v "^?? "`.empty?
  exit 1 unless system 'git commit -a -m "apply configuration changes"'
end
