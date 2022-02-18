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

  def update
    @event = Event.last
    @event.update! params.require(:event).permit(:name, :location, :date, :heat_range_cat, :heat_range_level, :heat_range_age, :intermix)
    redirect_to  settings_event_index_path , notice: "Event was successfully updated."
  end

  def index
    @people = Person.order(:name).includes(:level, :age, :studio)
    @heats = Heat.joins(entry: :lead).includes(:dance).order('number,people.back').all
  end
end