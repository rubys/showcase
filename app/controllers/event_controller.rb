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
      :intermix, :ballrooms, :heat_length, :heat_cost, :solo_cost, :multi_cost)
    anchor = nil
    anchor = 'prices' if params[:event][:heat_cost]
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
    user = ENV['REMOTE_USER']
    auth = YAML.load_file('config/tenant/auth.yml')[user]
    @showcases = YAML.load_file('config/tenant/showcases.yml')
    logos = Set.new

    @showcases.each do |year, sites|
      sites.each do |token, info|
        next if auth and not auth.include? token
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
    end

    ENV['SHOWCASE_LOGO'] = logos.first if logos.size == 1
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
end
