#!/usr/bin/env ruby

require 'websocket-client-simple'
require 'uri'
require 'json'
require 'net/http'

# Stress test configuration
URL = 'wss://smooth-nav.fly.dev/showcase/2025/vabeach/freestyles/cable'
PAGE_URL = 'https://smooth-nav.fly.dev/showcase/2025/vabeach/freestyles/public/heats'
FLY_APP = 'smooth-nav'
FLY_MACHINE = '286e340f714d38'

# Test parameters
num_connections = ARGV[0]&.to_i || 50
duration_seconds = ARGV[1]&.to_i || 30

puts "=" * 80
puts "WebSocket Stress Test"
puts "=" * 80
puts "Target URL: #{URL}"
puts "Connections: #{num_connections}"
puts "Duration: #{duration_seconds} seconds"
puts "Start time: #{Time.now}"
puts "=" * 80

# Get baseline memory
def get_memory_usage
  result = `fly ssh console --app #{FLY_APP} --machine #{FLY_MACHINE} --command "free -m" 2>/dev/null`
  if result =~ /Mem:\s+(\d+)\s+(\d+)\s+(\d+)/
    { total: $1.to_i, used: $2.to_i, free: $3.to_i }
  else
    nil
  end
end

def get_session_cookie
  uri = URI(PAGE_URL)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 5

  request = Net::HTTP::Get.new(uri)
  response = http.request(request)

  response['set-cookie']&.split(';')&.first
rescue => e
  puts "Warning: Failed to get session cookie: #{e.message}"
  nil
end

# Measure baseline memory
puts "\nMeasuring baseline memory..."
baseline_memory = get_memory_usage
if baseline_memory
  puts "Baseline memory: #{baseline_memory[:used]} MB used / #{baseline_memory[:total]} MB total"
else
  puts "Warning: Could not measure baseline memory"
end

# Get session cookie
puts "\nObtaining session cookie..."
session_cookie = get_session_cookie
if session_cookie
  puts "Session cookie obtained: #{session_cookie[0..50]}..."
else
  puts "Warning: No session cookie - connections may fail"
end

# Prepare headers
headers = {
  'Sec-WebSocket-Protocol' => 'actioncable-v1-json, actioncable-unsupported',
  'Origin' => 'https://smooth-nav.fly.dev'
}
headers['Cookie'] = session_cookie if session_cookie

# Connection tracking
connections = []
successful_connections = 0
failed_connections = 0
messages_received = 0
start_time = Time.now

# Create connections
puts "\nCreating #{num_connections} WebSocket connections..."
num_connections.times do |i|
  begin
    ws = WebSocket::Client::Simple.connect(URL, { headers: headers })

    ws.on :open do |event|
      successful_connections += 1

      # Subscribe to CurrentHeatChannel
      subscribe_msg = {
        command: 'subscribe',
        identifier: JSON.generate({
          channel: 'CurrentHeatChannel'
        })
      }
      ws.send(JSON.generate(subscribe_msg))

      if (successful_connections % 10 == 0) || (successful_connections == num_connections)
        print "\rConnected: #{successful_connections}/#{num_connections}"
        $stdout.flush
      end
    end

    ws.on :message do |event|
      messages_received += 1
    end

    ws.on :error do |event|
      # Silently track errors
    end

    ws.on :close do |event|
      # Connection closed
    end

    connections << ws

    # Small delay to avoid overwhelming the server during connection setup
    sleep 0.05 if (i + 1) % 10 == 0

  rescue => e
    failed_connections += 1
    puts "\nError creating connection #{i + 1}: #{e.message}"
  end
end

puts "\n\nConnection phase complete!"
puts "Successful: #{successful_connections}"
puts "Failed: #{failed_connections}"

# Wait for all connections to stabilize
puts "\nWaiting 5 seconds for connections to stabilize..."
sleep 5

# Measure memory after connections
puts "\nMeasuring memory with #{successful_connections} active connections..."
active_memory = get_memory_usage
if active_memory
  puts "Active memory: #{active_memory[:used]} MB used / #{active_memory[:total]} MB total"

  if baseline_memory
    memory_increase = active_memory[:used] - baseline_memory[:used]
    memory_per_connection = successful_connections > 0 ? memory_increase.to_f / successful_connections : 0

    puts "\n" + "=" * 80
    puts "MEMORY ANALYSIS"
    puts "=" * 80
    puts "Baseline memory: #{baseline_memory[:used]} MB"
    puts "Memory with connections: #{active_memory[:used]} MB"
    puts "Memory increase: #{memory_increase} MB"
    puts "Connections: #{successful_connections}"
    puts "Memory per connection: #{'%.2f' % memory_per_connection} MB (~#{'%.0f' % (memory_per_connection * 1024)} KB)"
    puts "=" * 80
  end
else
  puts "Warning: Could not measure active memory"
end

# Hold connections for the specified duration
puts "\nHolding connections for #{duration_seconds} seconds..."
remaining = duration_seconds
while remaining > 0
  print "\rTime remaining: #{remaining}s (Messages received: #{messages_received})  "
  $stdout.flush
  sleep 1
  remaining -= 1
end

# Measure final memory
puts "\n\nMeasuring final memory before closing connections..."
final_memory = get_memory_usage
if final_memory
  puts "Final memory: #{final_memory[:used]} MB used / #{final_memory[:total]} MB total"
end

# Close all connections
puts "\nClosing all connections..."
connections.each_with_index do |ws, i|
  begin
    ws.close
  rescue => e
    # Ignore close errors
  end

  if (i + 1) % 50 == 0
    print "\rClosed: #{i + 1}/#{connections.length}"
    $stdout.flush
  end
end

puts "\nAll connections closed."

# Wait a moment and measure memory after cleanup
sleep 3
puts "\nMeasuring memory after connection cleanup..."
cleanup_memory = get_memory_usage
if cleanup_memory
  puts "Cleanup memory: #{cleanup_memory[:used]} MB used / #{cleanup_memory[:total]} MB total"
end

# Final report
elapsed_time = Time.now - start_time
puts "\n" + "=" * 80
puts "STRESS TEST COMPLETE"
puts "=" * 80
puts "Total time: #{'%.1f' % elapsed_time} seconds"
puts "Connections created: #{num_connections}"
puts "Successful connections: #{successful_connections}"
puts "Failed connections: #{failed_connections}"
puts "Total messages received: #{messages_received}"

if baseline_memory && active_memory
  memory_increase = active_memory[:used] - baseline_memory[:used]
  memory_per_connection = successful_connections > 0 ? memory_increase.to_f / successful_connections : 0

  puts "\nMemory Statistics:"
  puts "  Baseline: #{baseline_memory[:used]} MB"
  puts "  Peak (with connections): #{active_memory[:used]} MB"
  puts "  Increase: #{memory_increase} MB"
  puts "  Per connection: #{'%.2f' % memory_per_connection} MB (~#{'%.0f' % (memory_per_connection * 1024)} KB)"

  if cleanup_memory
    recovered = active_memory[:used] - cleanup_memory[:used]
    puts "  After cleanup: #{cleanup_memory[:used]} MB (recovered #{recovered} MB)"
  end

  # Calculate capacity
  available = baseline_memory[:total] - baseline_memory[:used]
  if memory_per_connection > 0
    max_connections = (available / memory_per_connection).to_i
    puts "\nCapacity Estimate:"
    puts "  Available memory: #{available} MB"
    puts "  Estimated max connections: ~#{max_connections}"
    puts "  Safety margin (80% capacity): ~#{(max_connections * 0.8).to_i} connections"
  end
end

puts "=" * 80
puts "End time: #{Time.now}"
puts "=" * 80
