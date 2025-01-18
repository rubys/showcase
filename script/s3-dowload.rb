#! /usr/bin/env ruby

exit unless ENV['FLY_REGION']

if ENV['FLY_REGION'] == ENV['PRIMARY_REGION']
  Dir.chdir "/data" do
    if not Dir.exist? 'tigris'
      FileUtils.rm_rf 'storage'
    end

    system "rclone sync --progress tigris:showcase ./tigris"

    files = Dir.chdir('tigris') {Dir["*"]}
    files.each do |file|
      dest = file.sub(/(..)(..)/, 'storage/\1/\2/\1\2')
      if not File.exist? dest
        FileUtils.mkdir_p File.dirname(dest)
        File.link "tigris/#{file}", dest
      end
    end
  end
else
  FileUtils.rm_rf '/data/storage'
end
