class EventController < ApplicationController
  def root
    @judges = Person.where(type: 'Judge')
    @emcees = Person.where(type: 'Emcee')

    @event = Event.last
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
    @event.update! params.require(:event).permit(:name, :location, :date, :heat_range_cat, :heat_range_level, :heat_range_age)
    redirect_to  settings_event_index_path , notice: "Event was successfully updated."
  end
end
