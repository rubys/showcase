class EventController < ApplicationController
  def root
    @judges = Person.where(type: 'Judge')
    @emcees = Person.where(type: 'Emcee')

    @event = Event.last

    @heats = Heat.distinct.count(:number)
  end

  def settings
    @judges = Person.where(type: 'Judge')
    @emcees = Person.where(type: 'Emcee')

    @event = Event.last
    
    @ages = Age.all.size
    @levels = Level.all.size

    @packages = Billable.where.not(type: 'Order').order(:order).group_by(&:type)
    @options = Billable.where(type: 'Option').order(:order)

    if Studio.count == 0
      clone
    end
  end

  def summary
    @people = Person.includes(:level, :age, options: :option, package: {package_includes: :option}).
      all.group_by {|person| person.type}

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
  end

  def update
    @event = Event.last
    @event.update! params.require(:event).permit(:name, :location, :date, :heat_range_cat, :heat_range_level, :heat_range_age,
      :intermix, :ballrooms, :heat_length, :heat_cost, :solo_cost, :multi_cost, :max_heat_size, :package_required)
    anchor = nil
    anchor = 'description' if params[:event][:name]
    anchor = 'prices' if params[:event][:heat_cost]
    anchor = 'adjust' if params[:event][:intermix]
    redirect_to settings_event_index_path(anchor: anchor), notice: "Event was successfully updated."
  end

  def index
    @people = Person.order(:name).includes(:level, :age, :studio)
    @judges = Person.where(type: 'Judge').order(:name)
    @heats = Heat.joins(entry: :lead).
      includes(:scores, :dance, entry: [:level, :age, :lead, :follow]).
      order('number,people.back').all
  end

  def showcases
    if request.headers['HTTP_AUTHORIZATION']
      @user = Base64.decode64(request.headers['HTTP_AUTHORIZATION'].split(' ')[1]).split(':').first
    else
      @user = request.headers["HTTP_X_REMOTE_USER"]
    end

    auth = YAML.load_file('config/tenant/auth.yml')[@user]
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
      if auth
        sites.select! do |token, value|
          auth.include? token
        end
      end

      sites.each do |token, info|
        logos.add info[:logo] if info[:logo]
        if info[:events]
          info[:events].each do |subtoken, subinfo|
            db = "#{__dir__}/../..//db/#{year}-#{token}-#{subtoken}.sqlite3"
            begin
              subinfo.merge! JSON.parse(`sqlite3 --json #{db} "select date from events"`).first
            rescue
            end
          end
        else
          db = "#{__dir__}/../..//db/#{year}-#{token}.sqlite3"
          begin
            info.merge! JSON.parse(`sqlite3 --json #{db} "select date from events"`).first
          rescue
          end
        end
      end

      @scope = ENV.fetch("RAILS_APP_SCOPE", '')
      @scope = '/' + @scope unless @scope.empty?
    end

    if logos.size == 1
      EventController.logo = logos.first 
    else
      EventController.logo = nil
    end
  end

  def publish
    @public_url = URI.join(request.original_url, '../../public')
  end

  def database
    database = "db/#{ENV.fetch("RAILS_APP_DB") { Rails.env }}.sqlite3"
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
      old_ages = Age.order(:id)
      new_ages = params[:ages].strip.split("\n").map(&:strip).select {|age| not age.empty?} 

      if old_ages.length > new_ages.length
        Age.destroy_by(id: new_ages.length+1..)
      end

      new_ages.each_with_index do |new_age, index|
        category = new_age.split(':').first.strip
        description = new_age.split(':').last.strip

        if index >= old_ages.length
          Level.create(name: new_level, id: index+1)
        elsif old_ages[index].category != category or old_ages[index].description != description
          old_ages[index].update(category: category, description: description)
        end
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
          query(source, 'ages').each {|age| Age.create age}
        end
      end

      if tables[:settings]
        event = query(source, 'events').first
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
          query(source, 'levels').each {|level| Level.create level}
        end
      end

      if tables[:packages]
        Billable.transaction do
          PackageInclude.destroy_all
          Billable.destroy_all
          query(source, 'billables').each {|billable| Billable.create billable}
          query(source, 'package_includes').each {|pi| PackageInclude.create pi}
        end
      end

      if tables[:studios]
        Studio.transaction do
          StudioPair.destroy_all
          Studio.destroy_all
          query(source, 'studios').each do |studio|
            unless tables[:packages]
              studio.delete 'default_student_package_id'
              studio.delete 'default_professional_package_id'
              studio.delete 'default_guest_package_id'
            end

            Studio.create studio
          end
          query(source, 'studio-pairs').each {|pair| StudioPair.create pair}
        end
      end

      if tables[:people]
        Person.transaction do
          Person.destroy_all
          excludes = {}
          query(source, 'people').each do |person|
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
            query(source, 'categories').each {|category| Category.create category}
          end
        end

        if tables[:dances]
          Dance.transaction do
            Multi.destroy_all
            Dance.destroy_all

            query(source, 'dances').each do |dance|
              person.delete 'open_category_id' unless tables[:agenda]
              person.delete 'closed_category_id' unless tables[:agenda]
              person.delete 'solo_category_id' unless tables[:agenda]
              person.delete 'multi_category_id' unless tables[:agenda]
              Dance.create dance
            end

            query(source, 'multis').each {|multi| Multi.create multi}
          end
        end
      end
    end

    showcases

    @sources = []

    @showcases.each do |year, sites|
      sites.each do |token, info|
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

  def self.logo
    @@logo ||= ENV['SHOWCASE_LOGO'] || 'intertwingly.png'
  end

  def self.logo=(logo)
    @@logo = logo || 'intertwingly.png'
  end

  private

    def query(db, table, fields=nil)
      if fields
        Array(fields).map(&:inspect).join(', ')
      else
        fields = '*'
      end

      json = `sqlite3 --json db/#{db}.sqlite3 "select #{fields} from #{table}"`

      if json.empty?
        []
      else
        JSON.parse(json)
      end
    end
end