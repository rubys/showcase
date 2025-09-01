require 'open3'
require 'zlib'
require 'fileutils'
require 'time'
require 'erb'

class EventController < ApplicationController
  include DbQuery
  include HeatScheduler
  include ActiveStorage::SetCurrent
  include ShowcaseInventory

  skip_before_action :authenticate_user, only: %i[ counter showcases regions console upload navigator_config ]
  skip_before_action :current_event, only: %i[ navigator_config ]
  skip_before_action :verify_authenticity_token, only: :console

  permit_site_owners :root, trust_level: 25

  FONTS = {
    'Algerian' => 'Algerian Regular',
    'Arial' => 'Helvetica, Arial',
    'Berlin Sans FB' => 'Berlin Sans FB Demi Bold',
    'Bevan' => 'Bevan Regular',
    'Courier New' => 'Courier New, Courier',
    'Georgia' => 'Georgia',
    'Times New Roman' => 'Times New Roman, Times',
    'Trebuchet MS' => 'Trebuchet MS',
    'Verdana' => 'Verdana'
  }

  def landing
    @nologo = true
  end

  def root
    @judges = Person.includes(:judge).where(type: 'Judge').by_name
    @djs    = Person.where(type: 'DJ').by_name
    @emcees = Person.where(type: 'Emcee').by_name

    # If there are no DJs, but there are emcees, swap them as DJs will be used as emcees
    if @djs.empty? && !@emcees.empty?
      @djs, @emcees = @emcees, []
    end

    @event = Event.current || Event.create(name: 'Untitled Event', date: Time.now.strftime('%Y-%m-%d'), location: 'Unknown Location')

    @heats = Heat.where.not(number: ..0).distinct.count(:number)
    @unscheduled = Heat.where(number: 0).count

    # event navigation
    events = User.auth_event_list(@authuser)
    this_event = root_path.chomp('/')
    index = events.find_index(this_event)
    if index
      @prev = events[index-1] unless index == 0
      @next = events[index+1] unless index == events.length - 1
    end

    owner = ENV['RAILS_APP_OWNER']
    scope = ENV['RAILS_APP_SCOPE']
    root = ENV['RAILS_RELATIVE_URL_ROOT']
    if owner and scope and root
      events = Event.list.select {|event| event.owner == owner}
      index = events.find_index {|event| event.scope == scope}
      if index
        @up = File.join(root, 'studios', events[index].studio)
        @prev = File.join(root, events[index-1].scope) unless index == 0
        @next = File.join(root, events[index+1].scope) unless index == events.length - 1
      end
    end

    @browser_warn = browser_warn

    if @heats == 0 && @unscheduled == 0 && !Studio.where.not(name: 'Event Staff').any? && !ENV['RAILS_APP_OWNER'] == 'Demo'
      @cloneable = !@sources&.empty?
    end

    ActiveRecord::Base.connection.query_cache.clear unless Rails.env.production?

    render :root, status: (@browser_warn ? :upgrade_required : :ok)
  end

  def settings(status: :ok)
    @judges = Person.where(type: 'Judge').by_name
    @djs    = Person.where(type: 'DJ').by_name
    @emcees = Person.where(type: 'Emcee').by_name

    @event ||= Event.current

    @combine_open_and_closed = @event.heat_range_cat == 1

    @ages = Age.all.size
    @levels = Level.all.order(:id).map {|level| [level.name, level.id]}
    @solo_levels = @levels[1..]

    @packages = Billable.where.not(type: 'Order').ordered.group_by(&:type)
    @options = Billable.where(type: 'Option').ordered

    if not params[:tab] and Studio.pluck(:name).all? {|name| name == 'Event Staff'}
      clone unless ENV['RAILS_APP_OWNER'] == 'Demo'
    end

    if @sources and not @sources.empty?
      @tab = params[:tab] || 'Clone'
    else
      @tab = params[:tab] || 'Description'
    end

    if params[:tab] == 'Prices'
      @ages = Age.order(:id).pluck(:category, :id)
    elsif params[:tab] == 'Advanced'
      if not @event.track_ages
        @reset_ages = Person.where.not(age_id: 1).any? || Entry.where.not(age_id: 1).any?
      end

      if not @event.include_closed
        @reset_open = Heat.where(category: 'Closed').any?
      end

      if not @event.include_open
        @reset_closed = Heat.where(category: 'Open').any?
      end

      @reset_scores = Score.where.not(value: nil).any? or Score.where.not(comments: nil).any? or
        Score.where.not(good: nil).any? or Score.where.not(bad: nil).any?
    end

    render "event/settings/#{@tab.downcase}", layout: 'settings', status: status
  end

  def counter
    @event = Event.current
    @layout = 'mx-0 overflow-hidden'
  end

  def summary
    @people = Person.includes(:level, :age, :lead_entries, :follow_entries, options: :option, package: {package_includes: :option}).
      all.group_by {|person| person.type}
      # should .select(&:active?) be an option?

    @packages = Billable.where.not(type: 'Option').ordered.group_by(&:type).
      map {|type, packages| [type, packages.map {|package| [package, 0]}.to_h]}.to_h

    @options = Billable.where(type: 'Option').ordered.map {|package| [package, 0]}.to_h

    @people.each do |type, people|
      people.each do |person|
        options = person.options

        if person.package_id
          @packages[person.type][person.package] += 1
          person.package.package_includes.map(&:option).each do |option|
            @options[option] += 1 unless options.include? option
          end
        end

        options.map(&:option).each do |option|
          @options[option] += 1
        end
      end
    end

    @multi = Dance.where.not(multi_category: nil).count
    @pro_heats = Event.current.pro_heats

    @track_ages = Event.current.track_ages
  end

  def upload
    if request.post?
      file = params[:user][:file]
      name = File.basename(file.original_filename)
      dest = File.join('tmp', 'uploads', name)
      FileUtils.mkdir_p File.dirname(dest)
      IO.binwrite dest, file.read

      redirect_to root_path, notice: "#{file.original_filename} was successfully uploaded."
    end
  end

  def update
    @event = Event.current
    old_open_scoring = @event.open_scoring
    old_multi_scoring = @event.multi_scoring

    # Combine start_date and end_date if present
    if params[:event][:start_date]
      if params[:event][:start_date].present? &&params[:event][:end_date].present? && params[:event][:end_date] != params[:event][:start_date]
        params[:event][:date] = "#{params[:event][:start_date]} - #{params[:event][:end_date]}"
      else
        params[:event][:date] = params[:event][:start_date]
      end
      params[:event].delete(:start_date)
      params[:event].delete(:end_date)
    end

    @event.assign_attributes params.require(:event).permit(:name, :theme, :location, :date, :heat_range_cat, :heat_range_level, :heat_range_age,
      :intermix, :ballrooms, :column_order, :backnums, :track_ages, :heat_length, :solo_length, :open_scoring, :multi_scoring,
      :heat_cost, :solo_cost, :multi_cost, :max_heat_size, :package_required, :student_package_description, :payment_due,
      :counter_art, :judge_comments, :agenda_based_entries, :pro_heats, :assign_judges, :font_family, :font_size, :include_times,
      :include_open, :include_closed, :solo_level_id, :print_studio_heats, :independent_instructors, :closed_scoring, :heat_order, :dance_limit,
      :counter_color, :pro_heat_cost, :pro_solo_cost, :pro_multi_cost, :strict_scoring, :solo_scoring, :pro_am, :judge_recordings, :table_size)

    @event.dance_limit = nil if @event.dance_limit == 0

    @event.closed_scoring = "=" if @event.include_closed && !@event.include_open && @event.closed_scoring != '='

    redo_schedule = @event.max_heat_size_changed? || @event.heat_range_level_changed? || @event.heat_range_age_changed? || @event.heat_range_cat_changed?

    ok = @event.save

    if @event.open_scoring != old_open_scoring and @event.open_scoring != '#' and @event.open_scoring != '#'
      map = {
        "1" => "GH",
        "2" => "G",
        "3" => "S",
        "4" => "B",
        "GH" => "1",
        "G" => "2",
        "S" => "3",
        "B" => "4"
      }

      Score.transaction do
        Score.includes(:heat).where(heat: {category: 'Open'}).each do |score|
          score.update(value: map[score.value]) if map[score.value]
        end
      end
    end

    if @event.multi_scoring != old_multi_scoring and @event.multi_scoring != '#' and @event.multi_scoring != '#'
      map = {
        "1" => "GH",
        "2" => "G",
        "3" => "S",
        "4" => "B",
        "GH" => "1",
        "G" => "2",
        "S" => "3",
        "B" => "4"
      }

      Score.transaction do
        Score.includes(:heat).where(heat: {category: 'Multi'}).each do |score|
          score.update(value: map[score.value]) if map[score.value]
        end
      end
    end

    if ok
      # Redirect to tables index if table_size was updated
      if params[:event][:table_size]
        redirect_to tables_path, notice: "Default table size updated."
        return
      end

      tab = 'Description' if params[:event][:name]
      tab = 'Options' if params[:event][:intermix]
      tab = 'Prices' if params[:event][:heat_cost]
      tab = 'Heats' if params[:event][:max_heat_size]
      tab = 'Advanced' if params[:event][:solo_level_id]
      tab = params[:tab] if params[:tab]

      dest = settings_event_index_path(tab: tab)
      notice = "Event was successfully updated."

      if tab == 'Categories'
        dest = categories_path(settings: 'on')

        if redo_schedule
          schedule_heats
          notice = "#{Heat.maximum(:number).to_i} heats generated."
        end
      end

      redirect_to dest, notice: notice
    else
      settings(status: :unprocessable_content)
    end

    Event.current = Event.current
  end

  def index
    return select if params[:db]

    @people = Person.includes(:level, :age, :studio, :lead_entries, :follow_entries)
      .by_name
    @judges = Person.where(type: 'Judge').by_name
    @heats = Heat.joins(entry: :lead).
      includes(:scores, :dance, entry: [:level, :age, :lead, :follow]).
      order('number,people.back').all
  end

  def spreadsheet
    index

    @sheets = {}

    #***************************************************************************
    #                              Participants
    #***************************************************************************

    sheet = []

    headers = [
      'Name',
      'Type',
      'Role',
      'Back #',
      'Level',
      'Age',
      'Studio',
    ]

    @people.each do |person|
      sheet << headers.zip([
        person.name,
        person.type,
        person.role,
        person.back,
        person.level&.name,
        person.age&.category,
        person.studio&.name
      ]).to_h
    end

    @sheets['Participants'] = sheet

    #***************************************************************************
    #                                 Heats
    #***************************************************************************

    sheet = []

    if Event.current.column_order == 1
      headers = [
        'Number',
        'Student',
        'Open or Closed',
        'Dance',
        'Back #',
        'Lead',
        'Follow',
        'Level',
        'Category',
        'Studio',
      ] + @judges.map(&:first_name)

      @heats.each do |heat|
        scores = heat.scores
        scores_by_judge = @judges.map {|judge| scores.find {|score| score.judge == judge}&.value}
        sheet << headers.zip([
          heat.number,
          heat.entry.subject.name,
          heat.category,
          heat.dance.name,
          heat.entry.lead.back,
          heat.entry.lead.name,
          heat.entry.follow.name,
          heat.entry.level.name,
          heat.entry.subject_category,
          heat.entry.subject.studio.name,
          *scores_by_judge
        ]).to_h
      end
    else
      headers = [
        'Number',
        'Student',
        'Partner',
        'Open or Closed',
        'Dance',
        'Back #',
        'Level',
        'Category',
        'Studio',
      ] + @judges.map(&:first_name)

      @heats.each do |heat|
        scores = heat.scores
        scores_by_judge = @judges.map {|judge| scores.find {|score| score.judge == judge}&.value}
        sheet << headers.zip([
          heat.number,
          heat.entry.subject.name,
          heat.entry.partner(heat.entry.subject).name,
          heat.category,
          heat.dance.name,
          heat.entry.lead.back,
          heat.entry.level.name,
          heat.entry.subject_category,
          heat.entry.subject.studio.name,
          *scores_by_judge
        ]).to_h
      end
    end

    @sheets['Heats'] = sheet
  end

  def judge
    index

    @sheets = {}

    @judges.each do |judge|
      sheet = []
      assignments = judge.scores.pluck(:heat_id, :value).to_h

      if Event.current.column_order == 1
        headers = [
          'Heat',
          'Back #',
          'Student',
          'Open or Closed',
          'Dance',
          'Lead',
          'Follow',
          'Category',
          'Level',
          'Studio',
          'Score'
        ]

        @heats.each do |heat|
          next unless assignments.include? heat.id
          sheet << headers.zip([
            heat.number,
            heat.entry.lead.back,
            heat.entry.subject.name,
            heat.category,
            heat.dance.name,
            heat.entry.lead.name,
            heat.entry.follow.name,
            heat.entry.subject_category,
            heat.entry.level.name,
            heat.entry.subject.studio.name,
            assignments[heat.id]
          ]).to_h
        end
      else
        headers = [
          'Heat',
          'Back #',
          'Student',
          'Partner',
          'Open or Closed',
          'Dance',
          'Category',
          'Level',
          'Studio',
          'Score'
        ]

        @heats.each do |heat|
          next unless assignments.include? heat.id
          sheet << headers.zip([
            heat.number,
            heat.entry.lead.back,
            heat.entry.subject.name,
            heat.entry.partner(heat.entry.subject).name,
            heat.category,
            heat.dance.name,
            heat.entry.subject_category,
            heat.entry.level.name,
            heat.entry.subject.studio.name,
            assignments[heat.id]
          ]).to_h
        end
      end

      @sheets[judge.display_name] = sheet
    end
  end

  def showcases
    flash[:notice] ||= "Request submitted, check your email for updates." if params[:submitted]

    # Load base data
    @inventory = JSON.parse(File.read('tmp/inventory.json')) rescue []
    @showcases = YAML.load_file('config/tenant/showcases.yml')
    logos = Set.new

    regions = {}
    @showcases.each do |year, list|
      list.each  do |city, defn|
        region = defn[:region]
        next unless region  # Skip entries with nil regions
        regions[region] ||= []
        regions[region] << defn[:name]
      end
    end

    if params[:year]
      @showcases.select! {|year, sites| year.to_s == params[:year]}

      if params[:city] and @showcases[params[:year].to_i]
        city = params[:city]

        @showcases.each do |year, sites|
          sites.select! do |token, value|
            token == city
          end
        end

        @locale = Location.where(key: city).first&.locale
      end
    end

    @studio = params[:studio]
    if @studio
      @showcases.each do |year, sites|
        sites.select! {|token, info| token == @studio}
      end

      @locale = Location.where(key: @studio).first&.locale
    end

    @city = params[:city] || @studio

    @region = params[:region]
    if @region
      @showcases.each do |year, sites|
        sites.select! {|token, info| info[:region] == @region}
      end
    end

    @showcases.select! {|year, sites| !sites.empty?}
    if @showcases.empty?
      @map = RegionConfiguration.generate_map_data
      unless @map['studios'] && @map['studios'][@city]
        raise ActiveRecord::RecordNotFound
      end
    end

    if Rails.env.development? && @showcases.values.length == 1 && @showcases.values.first.values.length == 1
      # Only auto-redirect if this is NOT a studio page with multiple events
      city_info = @showcases.values.first.values.first
      if !@city || !city_info[:events] || city_info[:events].length == 1
        params[:db] = "#{@showcases.keys.first}-#{@showcases.values.first.keys.first}"
        return select
      end
    end

    # Build minimal inventory for filtered showcases
    build_inventory(full_inventory: false, showcases: @showcases)

    # Collect logos from showcases
    @showcases.each do |year, sites|
      sites.each do |token, info|
        logos.add info[:logo] || "arthur-murray-logo.gif"
      end
    end

    set_scope

    if logos.size == 1
      EventController.logo = logos.first
    else
      EventController.logo = nil
    end

    @up = '.'
    if params[:studio] || params[:city]
      if params[:year]
        @up = studio_events_path(params[:studio] || params[:city])
      elsif @map && @map['studios'] && @map['studios'][@city]
        region = @map['studios'][@city]['region']
        @up = region_path(region)
      else
        region = @showcases.values.first.values.first[:region]
        @up = region_path(region)
      end
    elsif params[:region]
      regions = regions.keys.sort
      index = regions.find_index(params[:region])
      @prev = region_path(regions[index-1]) if index > 0
      @next = region_path(regions[index+1]) if index < regions.length-1
    elsif params[:year]
      @up = '..'
      showcases = YAML.load_file('config/tenant/showcases.yml')
      years = showcases.keys.map(&:to_s).reverse
      index = years.find_index(params[:year])
      @prev = year_path(years[index-1]) if index > 0
      @next = year_path(years[index+1]) if index < years.length-1
    end
  end


  def regions
    return select if params[:year]
    return redirect_to root_path(db: params[:db]) if params[:db]

    @list = params[:list]
    @list ||= 'regions' if ENV['FLY_REGION']
    @list ||= 'studios'

    showcases = YAML.load_file('config/tenant/showcases.yml')
    @map = YAML.load_file('config/tenant/map.yml')

    @regions = {}
    @cities = {}

    showcases.each do |year, list|
      list.each  do |city, defn|
        @cities[defn[:name]] = city
        region = defn[:region]
        next unless region  # Skip entries with nil regions
        @regions[region] ||= []
        @regions[region] << defn[:name]
      end
    end

    @map['studios'].each do |key, studio|
      @cities[studio['name']] = key if studio['name']
    end

    @regions.each {|region, cities| cities.sort!.uniq!}

    (@map["regions"].values + @map['studios'].values).each do |point|
      if point['transform']
        x = point['x'].to_f
        y = point['y'].to_f
        transform = point['transform'][/\d.*\d/].split(',').map(&:to_f)
        point['x'] = x * transform[0] + y * transform[2] + transform[4]
        point['y'] = x * transform[1] + y * transform[3] + transform[5]
        point.delete('transform')
      end
    end

    @map['regions']
  end

  def region
    @region = params[:region]
    @passenger_status = ''
    @passenger_status = `sudo passenger-status` if ENV['FLY_MACHINE_ID'] || ENV['KAMAL_CONTAINER_NAME']

    logdir = Rails.root.join('log').to_s
    logdir = '/data/log' if Dir.exist?('/data/log')

    @logs = Dir["#{logdir}/*"].map {|file|
      [File.stat(file).mtime, File.basename(file)]
    }.sort
  end

  def region_log
    file = params[:file]

    render plain: IO.read(Rails.root.join('log', file).to_s)
  end

  def navigator_config
    config_path = Rails.root.join('config', 'navigator.yml')
    if File.exist?(config_path)
      render plain: File.read(config_path), content_type: 'text/plain'
    else
      render plain: "Navigator configuration not found", status: :not_found
    end
  end

  def logs
    unless User.index_auth?(@authuser)
      render file: File.expand_path('public/403-index.html', Rails.root),
        layout: false, status: :forbidden
      return
    end

    Bundler.with_original_env do
      if File.exist? '/opt/homebrew/bin/passenger-status'
        @passenger = `/opt/homebrew/bin/passenger-status`
      else
        @passenger = `passenger-status`
      end
    end

    @logs = []

    last_time = File.expand_path('~/logs/scu.time')
    FileUtils.mkdir_p File.dirname(last_time)

    start = File.stat(last_time).mtime rescue Time.now

    list = [
      'people/studio_list',
      '/certificates',
      '/drop',
      '/people/type',
      '/people/package'
    ]

    logdir = '/var/log/nginx'
    if Dir.exist? '/opt/homebrew/var/log/nginx'
      logdir = '/opt/homebrew/var/log/nginx'
    end

    logs = Dir["#{logdir}/access.log*"].sort_by {|name| (name[/\d+/]||99999999).to_i}.reverse
    logs.each do |log|
      users = `#{log.include?('z')?'z':''}egrep "[0-9] - \\w+ \\[" #{log} | grep -v /assets/ | grep -v ' - rubys \\['`
      unless users.empty?
        users.split("\n").reverse.each do |line|
          time = Time.parse(line[/\[(.*?)\]/, 1].sub(':', ' ')) rescue Time.now

          line = ERB::Util.h(line)

          line.sub!(/&quot;([A-Z]+) (\S+) (\S+)&quot; (\d+)/) do
            method, path, protocol, status = $1, $2, $3, $4
            if status == '200' and method == 'GET'
            elsif status == '302' and method == 'POST'
            elsif status == '303' and method == 'DELETE'
            elsif status == '304' and method == 'GET'
            elsif status == '204' and method == 'POST' and path.end_with? '/start_heat'
            elsif status == '200' and method == 'POST' and list.any? {|str| path.end_with? str}
            elsif status == '200' and method == 'POST' and path =~ %r{/scores/\d+/post$}
            elsif status == '101' and method == 'GET' and path.end_with? '/cable'
            else
              status = "<span style='background-color: orange'>#{status}</span>"
            end
            "\"#{method} <a href='#{path}'>#{path}</a> #{protocol}\" #{status}"
          end

          if time > start
            @logs << "<span style='background-color: yellow'>#{line}</span>"
          else
            @logs << line
          end
        end
        break
      end
    end

    FileUtils.touch last_time

    render layout: false
  end

  def publish
    @event = Event.current
    @public_url = URI.join(request.original_url, '../public')
    @fonts = FONTS

    # Wake up print server
    Thread.new do
      Net::HTTP.get_response(URI("https://smooth-pdf.fly.dev/"))
    end
  end

  def database
    dbpath = ENV.fetch('RAILS_DB_VOLUME') { 'db' }
    database = "#{dbpath}/#{ENV.fetch("RAILS_APP_DB") { Rails.env }}.sqlite3"
    render plain: `sqlite3 #{database} .dump`
  end

  def start_heat
    event = Event.current
    event.current_heat = params[:heat]
    event.save
    event.broadcast_replace_later_to "current-heat-#{ENV['RAILS_APP_DB']}",
      partial: 'event/heat', target: 'current-heat', locals: {event: event}
  end

  def ages
    if request.post?
      old_ages = Age.all
      new_ages = params[:ages].strip.split("\n").map(&:strip).
        select {|age| not age.empty?}.
        map {|age| age.split(':', 2).map(&:strip)}.to_h

      old_ids = old_ages.map {|age| [age.category, age.id]}.to_h
      mappings = new_ages.keys.zip(1..).
        map {|cat, idx| [old_ids[cat], idx]}.
        select {|old_idx, new_idx| old_idx != nil && old_idx != new_idx}.to_h

      new_ages.each_with_index do |(category, description), index|
        if index >= old_ages.length
          Age.create(category: category, description: description, id: index+1)
        elsif old_ages[index].category != category or old_ages[index].description != description
          old_ages[index].update(category: category, description: description)
        end
      end

      unless mappings.empty?
        Age.transaction do
          Person.all.each do |person|
            if mappings[person.age_id]
              Person.update(age_id: mappings[person.age_id])
            end
          end
        end
      end

      if old_ages.length > new_ages.length
        Age.destroy_by(id: new_ages.length+1..)
      end

      respond_to do |format|
        format.html { redirect_to settings_event_index_path(tab: 'Advanced'), notice: 'Ages successfully updated.' }
      end
    else
      @ages = Age.order(:id).pluck(:category, :description).
        map {|category, description| "#{category}: #{description}"}.join("\n")
    end
  end

  def levels
    if request.post?
      old_levels = Level.order(:id)
      new_levels = params[:levels].strip.split("\n").map(&:strip).select {|level| not level.empty?}

      if old_levels.length > new_levels.length
        Level.destroy_by(id: new_levels.length+1..)
      end

      new_levels.each_with_index do |new_level, index|
        if index >= old_levels.length
          Level.create(name: new_level, id: Level.pluck(:id).max+1)
        elsif old_levels[index].name != new_level
          old_levels[index].update(name: new_level)
        end
      end

      respond_to do |format|
        format.html { redirect_to settings_event_index_path(tab: 'Advanced'), notice: 'Levels successfully updated.' }
      end
    else
      @levels = Level.order(:id).pluck(:name).join("\n")
    end
  end

  def dances
    if request.post?
      dances = Dance.ordered.map {|dance| [dance.name, dance]}.to_h
      new_names = params[:dances].split(/\s\s+|\n|\t|,/).
        map {|str| str.gsub(/^\W+/, '')}.select {|name| not name.empty?}.uniq
      order = dances.values.map(&:order)

      remove = dances.keys - new_names
      Dance.destroy_by(name: remove) if remove.length > 0

      Dance.transaction do
        new_names.zip(order).each do |name, order|
          dance = dances[name]
          order ||= (Dance.maximum(:order) || 0) + 1

          if not dance
            dance = dances[name] = Dance.new(name: name, order: order)
            dance.save! validate: false
          elsif dance.order != order
            dance.order = order
            dance.save! validate: false
          end
        end

        raise ActiveRecord::Rollback unless dances.values.all? {|dance| dance.valid?}
      end

      respond_to do |format|
        format.html { redirect_to settings_event_index_path(tab: 'Advanced'), notice: 'Dances successfully updated.' }
      end
    else
      @dances = Dance.where(heat_length: nil).ordered.pluck(:name).join("\n")
    end
  end

  def clone
    if request.post?
      source = params[:source]
      tables = params.to_unsafe_h.select {|key, value| value == '1'}.
        map {|key, value| [key.to_sym, value]}.to_h

      if tables[:ages]
        Age.transaction do
          Person.destroy_all
          Age.destroy_all
          dbquery(source, 'ages').each {|age| Age.create age}
        end
      end

      if tables[:settings]
        event = dbquery(source, 'events').first
        event.delete 'id'
        event.delete 'name'
        event.delete 'date'
        event.delete 'theme'
        event.delete 'current_heat'
        event.delete 'locked'
        event.delete 'payment_due'
        Event.current.update(event)

        Feedback.transaction do
          Feedback.destroy_all
          dbquery(source, 'feedbacks').each {|feedback| Feedback.create feedback}
        end
      end

      if tables[:levels]
        Level.transaction do
          Person.destroy_all
          Level.destroy_all
          dbquery(source, 'levels').each {|level| Level.create level}
        end
      end

      if tables[:packages]
        Billable.transaction do
          PackageInclude.destroy_all
          Billable.destroy_all
          dbquery(source, 'billables').each {|billable| Billable.create billable}
          dbquery(source, 'package_includes').each {|pi| PackageInclude.create pi}
        end
      end

      if tables[:studios]
        Studio.transaction do
          StudioPair.destroy_all
          Studio.destroy_all
          dbquery(source, 'studios').each do |studio|
            unless tables[:packages]
              studio.delete 'default_student_package_id'
              studio.delete 'default_professional_package_id'
              studio.delete 'default_guest_package_id'
            end

            Studio.create studio
          end
          dbquery(source, 'studio-pairs').each {|pair| StudioPair.create pair}
        end
      end

      if tables[:people]
        Person.transaction do

          Person.destroy_all
          excludes = {}
          dbquery(source, 'people').each do |person|
            person.delete 'back'
            person.delete 'age_id' unless tables[:ages]
            person.delete 'level_id' unless tables[:levels]
            person.delete 'studio_id' unless tables[:studios]
            person.delete 'package_id'
            person.delete 'available'
            excludes[person['id']] = person.delete('exclude_id') if person['exclude_id']

            Person.create person
          end

          excludes.each do |id, exclude|
            Person.find(id).update(exclude_id: exclude)
          end

          Judge.destroy_all
          dbquery(source, 'judges').each {|judge| Judge.create judge}
        end

        if tables[:agenda]
          Category.transaction do
            Category.destroy_all
            dbquery(source, 'categories').each do |category|
              category.delete 'day'
              Category.create category
            end
          end
        end

        if tables[:dances]
          Dance.transaction do
            Multi.destroy_all
            Dance.destroy_all

            dbquery(source, 'dances').each do |dance|
              unless tables[:agenda]
                dance.delete 'open_category_id'
                dance.delete 'closed_category_id'
                dance.delete 'solo_category_id'
                dance.delete 'multi_category_id'

                dance.delete 'pro_open_category_id'
                dance.delete 'pro_closed_category_id'
                dance.delete 'pro_solo_category_id'
                dance.delete 'pro_multi_category_id'
              end
              Dance.create dance
            end

            dbquery(source, 'multis').each {|multi| Multi.create multi}
          end
        end
      end

      redirect_to settings_event_index_path,
        notice: "Cloned: #{tables.keys.map(&:to_s).join(", ")}"
    else

      showcases

      @sources = []

      @showcases.each do |year, sites|
        sites.each do |token, info|
          next unless User.authorized?(@authuser, info[:name])
          if info[:events]
            info[:events].each do |subtoken, subinfo|
              @sources << "#{year}-#{token}-#{subtoken}"
            end
          else
            @sources << "#{year}-#{token}"
          end
        end
      end

      @sources.delete ENV["RAILS_APP_DB"]

    end
  end

  def qrcode
    @public_url = URI.join(request.original_url, '../public')
    @event = Event.current
  end

  def self.logo
    @@logo ||= ENV['SHOWCASE_LOGO'] || 'intertwingly.png'
  end

  def self.logo=(logo)
    @@logo = logo == '' ? nil : logo
  end

  def import
    if request.post?
      db = ENV['RAILS_DB_VOLUME'] || 'db'

      name = File.basename(params[:file].original_filename)
      if name.end_with? '.sqlite3' or name == 'htpasswd'
        IO.binwrite File.join(db, name), params[:file].read
      elsif name.end_with? '.sqlite3.gz'
        Open3.capture2 'sqlite3', File.join(db, File.basename(name, '.gz')),
          stdin_data: Zlib::GzipReader.new(params[:file].tempfile).read
      end

      redirect_to root_path, notice: "#{params[:file].original_filename} was successfully imported."
    end
  end

  def console
    if request.post?
      body = request.body.read
      begin
        JSON.pretty_generate(JSON.parse(body)).lines.each do |line|
          logger.info line
        end
      rescue
        logger.warn body
      end
      render status: 202, json: {result: 'OK'}
    else
      root
    end
  end

  def web_console
    @event = Event.current
  end

  def select
    if params[:year] && params[:db].blank?
      return redirect_to root_path(
        db: "#{params[:year]}-#{params[:city]}-#{params[:event]}",
        year: params[:year],
      )
    end

    if params[:db]
      FileUtils.rm "tmp/pids/server.pid", force: true
      FileUtils.touch "tmp/reload.txt"

      Thread.new do
        sleep 0.5

        if params[:date].blank?
          Rails.logger.info "exec cd #{Rails.root} && bin/dev #{params[:db]}"
          Bundler.original_exec "cd #{Rails.root} && bin/dev #{params[:db]}"
        else
          Rails.logger.info "exec cd #{Rails.root} && bin/dev #{params[:db]} #{params[:date]}"
          Bundler.original_exec "cd #{Rails.root} && bin/dev #{params[:db]} #{params[:date]}"
        end
      end

      render file: 'public/503.html'
    elsif File.exist? "tmp/reload.txt"
      FileUtils.rm "tmp/reload.txt"
      redirect_to root_path
    else
      @scopy_stream = OutputChannel.register(:scopy)
      @hetzner_stream = OutputChannel.register(:hetzner)
      @flyio_stream = OutputChannel.register(:flyio)
      @vscode_stream = OutputChannel.register(:vscode)
      @db_browser_stream = OutputChannel.register(:db_browser)
      
      @dbs = Dir["db/2*.sqlite3"].
        sort_by {|name| File.mtime(name)}[-20..].
        map {|name| File.basename(name, '.sqlite3')}.
        reverse + ["index"]

      @dates = (0..19).map {|i| (Date.today-i).iso8601}
    end
  end

  def songs
    @region = params[:region]
    @attachments = {}

    table_check = <<-SQL
      SELECT name FROM sqlite_master WHERE type='table' AND name='active_storage_attachments';
    SQL

    query = <<-SQL
      SELECT name, record_type, record_id, key, filename, byte_size FROM active_storage_attachments 
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

    Dir.glob("#{ENV.fetch('RAILS_DB_VOLUME', "db")}/20*.sqlite3").each do |file|
      db = SQLite3::Database.new(file)
      next unless db.execute(table_check).any?
      event = File.basename(file, ".sqlite3")

      results = []

      begin
        results = db.execute(query)
      rescue SQLite3::Exception => e
        Rails.logger.error "SQLite3 Exception occurred: #{e}"
        exit
      end

      results.each do |result|
        result_hash = {
          name: result[0],
          record_type: result[1],
          record_id: result[2],
          file_name: result[4],
          file_size: result[5],
          event: event
        }
        key = result[3]
        @attachments[key] = result_hash
      end
    end

    # scan files

    @files = Set.new

    storage_dir = ENV.fetch('RAILS_STORAGE', 'storage').delete_suffix('/')
    Dir.glob("#{storage_dir}/**/*").each do |file|
      next unless file =~ /storage\/[a-z0-9]{2}\/[a-z0-9]{2}\/[a-z0-9]{28}$/
      @files.add(File.basename(file))
    end

    # scan tigris
    if File.exist?(config)
      remote = IO.read(config).include?('[showcase]') ? 'showcase' : 'tigris'
      stdout, stderr, status = Open3.capture3("rclone lsf #{remote}:showcase --files-only --max-depth 1")
      @tigris = Set.new(stdout.split("\n").reject(&:empty?))
    else
      @tigris = Set.new
    end

    @database = Set.new(@attachments.keys)
  end

private

  def set_scope
    @scope = ENV.fetch("RAILS_APP_SCOPE", '')
    @scope = '/' + @scope unless @scope.empty?
    @scope = ENV['RAILS_RELATIVE_URL_ROOT'] + '/' + @scope if ENV['RAILS_RELATIVE_URL_ROOT']
  end
end
