require "fileutils"
require "aws-sdk"

Dir.chdir Dir.home

files = Dir.glob("storage/*/*/*/*")
FileUtils.mkdir_p "flat-storage"

print "linking..."
dbs = Set.new
files.each do |file|
  base = File.basename(file)
  dbs.add file.split("/")[1]
  dest = "flat-storage/#{base}"
end

puts

Dir.chdir "flat-storage"

bucket_name = ENV["BUCKET_NAME"]

s3 = Aws::S3::Client.new(
  region: ENV["AWS_REGION"] || "auto",
  endpoint: ENV["AWS_ENDPOINT_URL_S3"] || "https://fly.storage.tigris.dev"
)

Dir["*"].sort.each do |file|
  print "\r#{file}"

  begin
    s3.head_object(
      bucket: bucket_name,
      key: file
    )

    next
  rescue Aws::S3::Errors::NotFound => e
  end

  s3.put_object(
    bucket: bucket_name,
    key: file,
    body: IO.read(file)
  )
end

Dir.chdir ".."

puts

dbpath = Dir.exist?("/data") ? "/data/db" : "db"
len = 0
dbs.sort.each do |db|
  print "\r#{db.ljust([db.length, len].max)}"
  system %{sqlite3 #{dbpath}/#{db}.sqlite3 "UPDATE active_storage_blobs SET service_name = 'tigris'"}
  len = db.length
end

puts
