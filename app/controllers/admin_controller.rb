class AdminController < ApplicationController
  include Configurator

  before_action :admin_home

  DEPLOYED = File.join(Rails.root, 'tmp', 'deployed.json')
  REGIONS = File.join(Rails.root, 'tmp', 'regions.json')

  def index
    if ENV['FLY_REGION']
      redirect_to 'https://rubix.intertwingly.net/showcase/admin',
        allow_other_host: true
      return
    end

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
      original = IO.read DEPLOYED rescue '{}'
      pending = JSON.parse(original)["pending"]
      stdout, status = Open3.capture2(fly, 'regions', 'list', '--json')

      if pending
        deployed = JSON.parse(stdout)
        deployed["pending"] = pending

        regions = deployed['ProcessGroupRegions'].
          find {|process| process['Name'] == 'app'}["Regions"]

        (pending['add'] || []).dup.each do |region|
          pending['add'].delete(region) if regions.include? region
        end

        (pending['delete'] || []).dup.each do |region|
          pending['delete'].delete(region) unless regions.include? region
        end

        stdout = JSON.pretty_generate(deployed)
      end

      if status.success? and stdout != original
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

    deployed = JSON.parse(IO.read(DEPLOYED))
    @regions = JSON.parse(IO.read(REGIONS))
    @pending = deployed["pending"] || {}
    @deployed = (deployed['ProcessGroupRegions'].
      find {|process| process['Name'] == 'app'}["Regions"]+ (@pending['add'] || [])).sort.
      map {|code| [code, @regions.find {|region| region['code'] == code}]}.to_h

    exists = Region.where(code: @deployed.keys).pluck(:code)
    @deployed.each do |code, region|
      next if exists.include? code
      Region.create!(
        code: code,
        type: 'fly',
        location: region['name'],
        latitude: region['latitude'],
        longitude: region['longitude']
      )
    end

    Region.where.not(code: @deployed.keys).each do |region|
      region.destroy! if region.type == "fly"
    end
  end

  def show_region
    @primary_region = Tomlrb.load_file('fly.toml')['primary_region'] || 'iad'
    @pending = JSON.parse(IO.read(DEPLOYED))['pending'] || {}
    @code = params[:code]
    @region = JSON.parse(IO.read(REGIONS)).
      find {|region| region['Code'] == @code}
    render :region
  end

  def destroy_region
    code = params[:code]
    deployed = JSON.parse(IO.read(DEPLOYED))
    deployed["pending"] ||= {}
    deployed["pending"]["delete"] ||= []
    if deployed["pending"]["add"]&.include? code
      deployed["pending"]["add"].delete code
      IO.write(DEPLOYED, JSON.pretty_generate(deployed))
      notice = "Region #{code} pending addition undone."
    elsif not deployed["pending"]["delete"].include? code
      deployed["pending"]["delete"] << code
      IO.write(DEPLOYED, JSON.pretty_generate(deployed))
      notice = "Region #{code} deletion pending."
    else
      notice = "Region #{code} already pending deletion."
    end

    generate_map

    respond_to do |format|
      format.html { redirect_to admin_regions_url, status: 303, notice: notice }
      format.json { head :no_content }
    end
  end

  def new_region
    deployed = JSON.parse(IO.read(DEPLOYED))
    pending = deployed["pending"]
    deployed = deployed['ProcessGroupRegions'].
      find {|process| process['Name'] == 'app'}["Regions"]
    if pending
      deployed += pending["add"] || []
      deployed -= pending["delete"] || []
    end

    @regions = JSON.parse(IO.read(REGIONS)).
      select {|region| not deployed.include?(region['Code'])}.
      map {|region| [region['Name'], region['Code']]}.to_h
  end

  def create_region
    code = params[:code]
    deployed = JSON.parse(IO.read(DEPLOYED))
    deployed["pending"] ||= {}
    deployed["pending"]["add"] ||= []
    if deployed["pending"]["delete"]&.include? code
      deployed["pending"]["delete"].delete code
      IO.write(DEPLOYED, JSON.pretty_generate(deployed))
      notice = "Region #{code} pending deletion undone."
    elsif not deployed["pending"]["add"].include? code
      deployed["pending"]["add"] << code
      IO.write(DEPLOYED, JSON.pretty_generate(deployed))
      notice = "Region #{code} addition pending."
    else
      notice = "Region #{code} already pending deletion."
    end

    generate_map

    respond_to do |format|
      format.html { redirect_to admin_regions_url, status: 303, notice: notice }
      format.json { head :no_content }
    end
  end

  def apply
    @stream = OutputChannel.register(:apply)

    generate_showcases
    before = YAML.load_file('config/tenant/showcases.yml').values.reduce {|a, b| a.merge(b)}
    after = YAML.load_file('db/showcases.yml').values.reduce {|a, b| a.merge(b)}

    @move = {}
    after.to_a.sort.each do |site, info|
      was = before[site]
      next unless was
      next if was[:region] == info[:region]
      @move[site] = {from: was[:region], to: info[:region]}
    end

    previous = parse_showcases('config/tenant/showcases.yml')
    showcases = parse_showcases('db/showcases.yml')
    @showcases_modified = showcases - previous
    @showcases_removed = previous - showcases - @showcases_modified

    deployed = JSON.parse(IO.read(DEPLOYED))
    @pending = deployed['pending'] || {}
    regions = deployed['ProcessGroupRegions'].
      find {|process| process['Name'] == 'app'}["Regions"]

    (@pending['add'] ||= []).select! {|region| !regions.include? region}
    (@pending['delete'] ||= []).select! {|region| regions.include? region}
  end

private

  def parse_showcases(file)
    showcases = []

    YAML.load_file(file).each do |year, studios|
      studios.each do |token, studio|
        if studio[:events]
          studio[:events].each_with_index do |(event, info), index|
            showcases << [year, token, info[:name], index]
          end
        else
          showcases << [year, token, 'Showcase', -1]
        end
      end
    end

    showcases
  end
end
