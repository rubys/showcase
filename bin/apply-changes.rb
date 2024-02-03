#!/usr/bin/env ruby
require 'json'
require 'tomlrb'

fly = File.join(Dir.home, '.fly/bin/flyctl')

primary_region = Tomlrb.parse(IO.read 'fly.toml')['primary_region']

# index.sqlite3
unless `rsync -i --dry-run db/index.sqlite3 smooth:/data/db/`.empty?
  exit 1 unless system "bin/user-update"
end

# create machine(s)
pending = JSON.parse(IO.read('tmp/deployed.json'))['pending'] || {}

if pending['add'] and not pending['add'].empty?
  machines = JSON.parse(`#{fly} machines list --json`)
  primary = machines.find {|machine|
    machine['region'] == primary_region && machine['config']['env']['FLY_PROCESS_GROUP'] == 'app'
  }
end

(pending['add'] || []).each do |region|
  cmd = [fly, 'machine', 'clone', primary['id'], '--region', region, '--verbose']

  volumes = JSON.parse(`#{fly} volumes list --json`)
  volume = volumes.find do |volume| 
    volume['region'] == region && volume['attached_machine_id'] == nil
  end

  if volume
    # protect against volume attached to a machine that is destroyed
    status = JSON.parse(`#{fly} volumes show #{volume['id']} --json`)
    if status['attached_machine_id'] == nil
      cmd += ['--attach-volume', volume['id']]
    end
  end

  exit 1 unless system *cmd
end

# create map, update showcases
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

# deploy changes
unless `git status --short | grep -v "^?? "`.empty?
  exit 1 unless system "#{fly} deploy"
end

# ensure that there is only one machine per region
machines = JSON.parse(`#{fly} machines list --json`)
machines.select! {|machine|
  machine['config']['env']['FLY_PROCESS_GROUP'] == 'app'
}

machines_by_region = machines.map {|machine| [machine['region'], machine['id']]}.sort_by(&:last).group_by(&:first)

if machines_by_region.any? {|region, machines| machines.length > 1}
  machines_by_region.each do |region, machines|
     machines.each_with_index do |machine, index|
       exit 1 unless system "#{fly} machine destroy --force #{machine} --verbose" if index > 0
     end
  end
  machines = JSON.parse(`#{fly} machines list --json`)
end

# process pending delete queue
(pending['delete'] || []).each do |region|
  machine = machines.find {|machine| machine['region'] == region}
  exit 1 unless system "#{fly} machine destroy --force #{machine['id']} --verbose" if machine
end

# push changes
unless `git status --short | grep -v "^?? "`.empty?
  exit 1 unless system 'git commit -a -m "apply configuration changes"'
  exit 1 unless system 'git push'
end
