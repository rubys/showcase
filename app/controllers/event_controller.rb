require 'open3'
require 'zlib'
require 'fileutils'
require 'time'
require 'erb'

class EventController < ApplicationController
  include DbQuery
  include ActiveStorage::SetCurrent

  skip_before_action :authenticate_user, only: %i[ counter, showcases ]

  def root
    @judges = Person.where(type: 'Judge')
    @djs    = Person.where(type: 'DJ')
    @emcees = Person.where(type: 'Emcee')

    @event = Event.last

    @heats = Heat.where(number: 1..).distinct.count(:number)

    # event navigation
    events = User.auth_event_list(@authuser)
    this_event = root_path.chomp('/')
    index = events.find_index(this_event)
    if index
      @prev = events[index-1] unless index == 0
      @next = events[index+1] unless index == events.length - 1
    end
  end

  def settings
    @judges = Person.where(type: 'Judge')
    @djs    = Person.where(type: 'DJ')
    @emcees = Person.where(type: 'Emcee')

    @event ||= Event.last
    
    @ages = Age.all.size
    @levels = Level.all.size

    @packages = Billable.where.not(type: 'Order').order(:order).group_by(&:type)
    @options = Billable.where(type: 'Option').order(:order)

    if Studio.pluck(:name).all? {|name| name == 'Event Staff'}
      clone
    end
  end

  def counter
    @event = Event.last
    @layout = 'mx-0 overflow-hidden'
  end

  def summary
    @people = Person.includes(:level, :age, :lead_entries, :follow_entries, options: :option, package: {package_includes: :option}).
      all.select(&:active?).group_by {|person| person.type}

    @packages = Billable.where.not(type: 'Option').order(:order).group_by(&:type).
      map {|type, packages| [type, packages.map {|package| [package, 0]}.to_h]}.to_h

    @options = Billable.where(type: 'Option').order(:order).map {|package| [package, 0]}.to_h

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

    @track_ages = Event.last.track_ages
  end

  def update
    @event = Event.last
    old_open_scoring = @event.open_scoring
    old_multi_scoring = @event.multi_scoring
    ok = @event.update params.require(:event).permit(:name, :theme, :location, :date, :heat_range_cat, :heat_range_level, :heat_range_age,
      :intermix, :ballrooms, :column_order, :backnums, :track_ages, :heat_length, :solo_length, :open_scoring, :multi_scoring,
      :heat_cost, :solo_cost, :multi_cost, :max_heat_size, :package_required, :student_package_description, :payment_due,
      :counter_art, :judge_comments)

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

    anchor = nil

    if ok
      anchor = 'description' if params[:event][:name]
      anchor = 'prices' if params[:event][:heat_cost]
      anchor = 'adjust' if params[:event][:intermix]
      redirect_to settings_event_index_path(anchor: anchor), notice: "Event was successfully updated."
    else
      settings
      render :settings, status: :unprocessable_entity
    end
  end

  def index
    @people = Person.order(:name).includes(:level, :age, :studio)
    @judges = Person.where(type: 'Judge').order(:name)
    @heats = Heat.joins(entry: :lead).
      includes(:scores, :dance, entry: [:level, :age, :lead, :follow]).
      order('number,people.back').all
  end

  def showcases
    auth = YAML.load_file('config/tenant/auth.yml')[@authuser]
    @showcases = YAML.load_file('config/tenant/showcases.yml')
    logos = Set.new

    if params[:year]
      @showcases.select! {|year, sites| year.to_s == params[:year]}

      if params[:city] and @showcases[params[:year].to_i]
        @showcases.each do |year, sites|
          sites.select! do |token, value|
            token == params[:city]
          end
        end
      end

      if @showcases.empty? or @showcases.all? {|year, sites| sites.empty?}
        raise ActiveRecord::RecordNotFound
      end
    end

    @showcases.each do |year, sites|
      if auth and false # disable
        sites.select! do |token, value|
          auth.include? token
        end
      end

      sites.each do |token, info|
        logos.add info[:logo] if info[:logo]
        if info[:events]
          info[:events].each do |subtoken, subinfo|
            db = "#{year}-#{token}-#{subtoken}"
            begin
              subinfo.merge! dbquery(db, 'events', 'date').first
            rescue
            end
          end
        else
          db = "#{year}-#{token}"
          begin
            info.merge! dbquery(db, 'events', 'date').first
          rescue
          end
        end
      end

      @scope = ENV.fetch("RAILS_APP_SCOPE", '')
      @scope = '/' + @scope unless @scope.empty?
      @scope = ENV['RAILS_RELATIVE_URL_ROOT'] + '/' + @scope if ENV['RAILS_RELATIVE_URL_ROOT']
    end

    if logos.size == 1
      EventController.logo = logos.first 
    else
      EventController.logo = nil
    end
  end

  def logs
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

	  line.sub! /&quot;([A-Z]+) (\S+) (\S+)&quot; (\d+)/ do
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
    @public_url = URI.join(request.original_url, '../public')
  end

  def database
    dbpath = ENV.fetch('RAILS_DB_VOLUME') { 'db' }
    database = "#{dbpath}/#{ENV.fetch("RAILS_APP_DB") { Rails.env }}.sqlite3"
    render plain: `sqlite3 #{database} .dump`
  end

  def start_heat
    event = Event.last
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
        format.html { redirect_to settings_event_index_path(anchor: 'advanced') }
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
          Level.create(name: new_level, id: index+1)
        elsif old_levels[index].name != new_level
          old_levels[index].update(name: new_level)
        end
      end

      respond_to do |format|
        format.html { redirect_to settings_event_index_path(anchor: 'advanced') }
      end
    else
      @levels = Level.order(:id).pluck(:name).join("\n")
    end
  end

  def dances
    if request.post?
      dances = Dance.order(:order).map {|dance| [dance.name, dance]}.to_h
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
        format.html { redirect_to settings_event_index_path(anchor: 'advanced') }
      end
    else
      @dances = Dance.where(heat_length: nil).order(:order).pluck(:name).join("\n")
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
        event.delete 'current_heat'
        Event.first.update(event)
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
            person.delete 'age_id' unless tables[:ages]
            person.delete 'level_id' unless tables[:levels]
            person.delete 'studio_id' unless tables[:studios]
            person.delete 'package_id'
            excludes[person['id']] = person.delete('exclude_id') if person['exclude_id']

            Person.create person
          end

          excludes.each do |id, exclude|
            person.find(id).update(exlude_id: exclude)
          end
        end

        if tables[:agenda]
          Category.transaction do
            Category.destroy_all
            dbquery(source, 'categories').each {|category| Category.create category}
          end
        end

        if tables[:dances]
          Dance.transaction do
            Multi.destroy_all
            Dance.destroy_all

            dbquery(source, 'dances').each do |dance|
              person.delete 'open_category_id' unless tables[:agenda]
              person.delete 'closed_category_id' unless tables[:agenda]
              person.delete 'solo_category_id' unless tables[:agenda]
              person.delete 'multi_category_id' unless tables[:agenda]
              Dance.create dance
            end

            dbquery(source, 'multis').each {|multi| Multi.create multi}
          end
        end
      end
    end

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

  def qrcode
    @public_url = URI.join(request.original_url, '../public')
    @event = Event.first
  end

  def self.logo
    @@logo ||= ENV['SHOWCASE_LOGO'] || 'intertwingly.png'
  end

  def self.logo=(logo)
    @@logo = logo || 'intertwingly.png'
  end

  def import
    if request.post?
      db = ENV['RAILS_DB_VOLUME'] || 'db'

      name = File.basename(params[:file].original_filename)
      if name.end_with? '.sqlite3' or name == 'htpasswd'
        IO.binwrite File.join(db, name), params[:file].read
      elsif name.end_with? '.sqlite3.gz'
        stdout, status = Open3.capture2 'sqlite3', File.join(db, File.basename(name, '.gz')),
          stdin_data: Zlib::GzipReader.new(params[:file].tempfile).read 
      end

      redirect_to root_path, notice: "#{params[:file].original_filename} was successfully imported."
    end
  end
end
