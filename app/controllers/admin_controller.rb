class AdminController < ApplicationController
  DEPLOYED = File.join(Rails.root, 'tmp', 'deployed.json')
  REGIONS = File.join(Rails.root, 'tmp', 'regions.json')

  def index
    showcases = YAML.load_file('config/tenant/showcases.yml')

    cities = Set.new
    @events = 0

    showcases.each do |year, info|
      info.each do |city, defn|
        cities << city
        if defn[:events]
          @events += defn[:events].length
        else
          @events += 1
        end
      end
    end

    @cities = cities.count
  end

  def regions
    fly = File.join(Dir.home, '.fly/bin/flyctl')

    thread1 = Thread.new do
      stdout, status = Open3.capture2(fly, 'regions', 'list', '--json')
      if status.success? and stdout != (IO.read DEPLOYED rescue nil)
        IO.write DEPLOYED, stdout
      end
    end

    thread2 = Thread.new do
      stdout, status = Open3.capture2(fly, 'platform', 'regions', '--json')
      if status.success? and stdout != (IO.read REGIONS rescue nil)
        IO.write REGIONS, stdout
      end
    end

    thread1.join
    thread2.join

    @regions = JSON.parse(IO.read(REGIONS))
    @deployed = JSON.parse(IO.read(DEPLOYED))['ProcessGroupRegions'].
      find {|process| process['Name'] == 'app'}["Regions"].sort.
      map {|code| [code, @regions.find {|region| region['Code'] == code}]}.to_h
  end

  def show_region
    @primary_region = Tomlrb.load_file('fly.toml')['primary_region'] || 'iad'
    @code = params[:code]
    logger.info @code
    @region = JSON.parse(IO.read(REGIONS)).
      find {|region| region['Code'] == @code}
    logger.info @region
    render :region
  end
end
