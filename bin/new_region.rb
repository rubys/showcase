#!/usr/bin/env ruby

require 'tomlrb'
require 'json'

region = ARGV[0]

primary_region = Tomlrb.load_file('fly.toml')['primary_region'] || 'iad'

machines = JSON.parse(`fly machines list --json`)

primary = machines.find {|machine| machine['region'] == primary_region} ||
          machines.first

if machines.find {|machine| machine['region'] == region}
  STDERR.puts "*** Aborting, machine already found in region #{region}"
  exit 1
else
  system "fly machine clone #{primary['id']} --region #{region}"
end
