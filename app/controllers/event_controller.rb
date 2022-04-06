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
  end

  def summary
    @people = Person.all.group_by {|person| person.type}
  end

  def update
    @event = Event.last
    @event.update! params.require(:event).permit(:name, :location, :date, :heat_range_cat, :heat_range_level, :heat_range_age, :intermix)
    redirect_to settings_event_index_path , notice: "Event was successfully updated."
  end

  def index
    @people = Person.order(:name).includes(:level, :age, :studio)
    @judges = Person.where(type: 'Judge').order(:name)
    @heats = Heat.joins(entry: :lead).
      includes(:scores, :dance, entry: [:level, :age, :lead, :follow]).
      order('number,people.back').all
  end

  def showcases
    @showcases = YAML.load_file('config/tenant/showcases.yml')

    @showcases.each do |year, sites|
      sites.each do |token, info|
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
  end

  def publish
    @public_url = URI.join(request.original_url, '../../public')
  end

  def start_heat
    event = Event.last
    event.current_heat = params[:heat]
    event.save
    event.broadcast_replace_later_to "current-heat-#{ENV['RAILS_APP_DB']}",
      partial: 'event/heat', target: 'current-heat', locals: {event: event}
  end
end
