#!/usr/bin/env ruby

require 'uri'
require 'json'

migrations = Dir["db/migrate/2*"].map {|name| name[/\d+/]}

ARGV.each do |database|
  lock_file = database.sub('.sqlite3', '.lock')
  applied = []

  File.open(lock_file, 'w') do |file|
    if file.flock(File::LOCK_EX)
      if File.exist?(database) and File.size(database) > 0
        begin
          applied = JSON.parse(`sqlite3 #{database} "select version from schema_migrations" --json`).map(&:values).flatten
        rescue
        end
      end

      unless (migrations - applied).empty?
        ENV['DATABASE_URL'] = "sqlite3://#{File.realpath(database)}"

        # only run migrations in one place - fly.io; rely on rsync to update others
        system 'bin/rails db:prepare'

        # not sure why this is needed...
        count = `sqlite3 #{database} "select count(*) from events"`.to_i
        system 'bin/rails db:seed' if count == 0
      end

      file.flock(File::LOCK_UN)
    end
  end

  File.unlink(lock_file) if File.exist?(lock_file)
end