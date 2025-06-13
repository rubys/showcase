#!/usr/bin/env ruby

require 'sqlite3'
require 'open3'
require 'set'
require 'pathname'

# scan databases

attachments = {}

table_check = <<-SQL
  SELECT name FROM sqlite_master WHERE type='table' AND name='active_storage_attachments';
SQL

query = <<-SQL
  SELECT name, record_type, record_id, key FROM active_storage_attachments 
  LEFT JOIN active_storage_blobs ON
  active_storage_blobs.id = active_storage_attachments.blob_id
SQL

config = "#{Dir.home}/.config/rclone/rclone.conf"
if ENV['BUCKET_NAME'] && !Dir.exist?(File.dirname(config))
FileUtils.mkdir_p File.dirname(config)
  File.write config, <<~CONFIG unless File.exist? config
    [tigris]
    type = s3
    provider = AWS
    endpoint = https://fly.storage.tigris.dev
    access_key_id = #{ENV['AWS_ACCESS_KEY_ID']}
    secret_access_key = #{ENV['AWS_SECRET_ACCESS_KEY']}
  CONFIG
end

Dir.glob("db/20*.sqlite3").each do |file|
  db = SQLite3::Database.new(file)
  next unless db.execute(table_check).any?
  event = File.basename(file, ".sqlite3")

  results = []

  begin
    results = db.execute(query)
  rescue SQLite3::Exception => e
    puts "Exception occurred"
    puts e
    exit
  end

  results.each do |result|
    result_hash = {
      name: result[0],
      record_type: result[1],
      record_id: result[2],
      event: event
    }
    key = result[3]
    attachments[key] = result_hash
  end
end

# scan files

files = Set.new
Dir.glob("storage/**/*").each do |file|
  files.add(File.basename(file))
end

# scan tigris
stdout, stderr, status = Open3.capture3("rclone lsf showcase:showcase --files-only --max-depth 1")
tigris = Set.new(stdout.split("\n").reject(&:empty?))

database = Set.new(attachments.keys)

puts "Files in storage but not in database:"
puts (files - database).size

puts "Files in database but not in storage:"
(database - files).each do |file|
  puts "#{file} #{attachments[file]}"
end

puts "Files in tigris but not in storage:"
puts (tigris - files).size

puts "Files in storage but not in tigris:"
puts (files - tigris).size

puts "Files in tigris but not in database:"
puts (tigris - database).size

puts "Files in database but not in tigris:"
(database - tigris).each do |file|
  puts "#{files.include?(file)} #{file} #{attachments[file]}"
end