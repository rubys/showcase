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
    
    @categories = Person.distinct.pluck(:category).compact.length
    @levels = Person.distinct.pluck(:level).compact.length
  end

  def update
    @event = Event.last
    STDERR.puts params
    @event.update! params.require(:event).permit(:name, :location, :date, :heat_range_cat, :heat_range_level, :heat_range_age)
    redirect_to  settings_event_index_path , notice: "Event was successfully updated."
  end
end