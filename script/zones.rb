#!/usr/bin/evn ruby

require 'json'

volumes = JSON.parse(`fly volumes list --json`)

volumes.sort_by { |v| [v['region'], v['zone']] }.each do |volume|
  next unless volume['attached_machine_id']
  puts "#{volume['region']} #{volume['zone']} #{volume['attached_machine_id']}"
end