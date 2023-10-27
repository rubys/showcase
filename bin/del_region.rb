#!/usr/bin/env ruby

require 'tomlrb'
require 'json'

region = ARGV[0]

machines = JSON.parse(`fly machines list --json`)

machine = machines.find {|machine| machine['region'] == region}

if machine
  system "fly machine destroy #{machine['id']} --force"
else
  STDERR.puts "*** No machine found in region #{region}"
  exit 1
end
