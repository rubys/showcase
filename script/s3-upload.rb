require "fileutils"
require "aws-sdk-s3"

Dir.chdir (Dir.exist?("/data") ? "/data" : Dir.home)
WORKDIR = "flat-storage"

files = Dir.glob("storage/*/*/*/*")
cleanup = not Dir.exist? WORKDIR
FileUtils.mkdir_p WORKDIR

print "linking..."
dbs = Set.new
files.each do |file|
  base = File.basename(file)
  dbs.add file.split("/")[1]
  dest = "#{WORKDIR}/#{base}"
  File.link file, dest unless File.exist? dest
end

puts

Dir.chdir WORKDIR

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
FileUtils.rm_rf WORKDIR if cleanup

puts

dbpath = Dir.exist?("/data") ? "/data/db" : "db"
len = 0
dbs.sort.each do |db|
  print "\r#{db.ljust([db.length, len].max)}"
  system %{sqlite3 #{dbpath}/#{db}.sqlite3 "UPDATE active_storage_blobs SET service_name = 'tigris'"}
  len = db.length
end

puts
