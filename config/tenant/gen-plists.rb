require 'erb'
require 'yaml'

Dir.chdir __dir__

LAUNCH_AGENTS = "#{Dir.home}/Library/LaunchAgents"

agents = Dir["#{LAUNCH_AGENTS}/showcase-*"].map do |file|
  [File.basename(file, '.plist'), IO.read(file)]
end.to_h

@git_path = File.realpath('../..')

showcases = YAML.load_file("showcases.yml")

showcases.each do |year, list|
  list.each do |token, info|
    @label = "#{year}-#{token}"
    @redis = "#{year}_#{token}"
    @scope = "#{year}/#{token}"
    @port = info[:port]
    template = ERB.new(IO.read("plist.erb"))
    agent = template.result(binding)
    showcase = "showcase-#{@label}"

    if agents.delete(showcase) != agent
      IO.write("#{LAUNCH_AGENTS}/#{showcase}.plist", agent)
      puts "+ #{LAUNCH_AGENTS}/#{showcase}.plist"
    end
  end
end

agents.keys.each do |showcase|
  puts "- #{LAUNCH_AGENTS}/#{showcase}.plist"
  # File.unlink("#{LAUNCH_AGENTS}/#{showcase}.plist")
end
