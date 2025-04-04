#!/usr/bin/env ruby

if ARGV.empty?
  database = "db/2025-boston-april.sqlite3"
else
  database = ARGV.first
end

if !defined? Rails
  exec "bin/run", database, $0, *ARGV
end

require 'csv'
include Compmngr

if ARGV[1].ends_with?(".csv")
  input = CSV.read(ARGV[1])
elsif ARGV[1].ends_with?(".txt")
  input = CSV.read(ARGV[1], col_sep: "\t")
elsif ARGV[1].ends_with?(".xls") || ARGV[1].ends_with?(".xlsx")
  dest = File.join(Rails.root, "tmp", File.basename(ARGV[1], ".*") + ".csv")
  system "ssconvert", ARGV[1], dest
  input = CSV.read(dest)
else
  STDERR.puts "Unknown file type: #{ARGV[1]}"
  exit 1
end

import_from_compmngr input