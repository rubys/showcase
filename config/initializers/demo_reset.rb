if ENV["RAILS_APP_OWNER"] == "Demo"
  database = URI.parse(ENV["DATABASE_URL"]).path

  if File.exist? "#{database}.time"
    if Time.now.to_i - File.mtime("#{database}.time").to_i > 3600
      FileUtils.cp "#{database}.seed", database, preserve: true
      FileUtils.rm "#{database}.time"

      storage = ENV["RAILS_STORAGE"]
      FileUtils.rm_rf storage
      FileUtils.mkdir_p storage
    end
  end
end
