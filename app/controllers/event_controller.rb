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

    @dances = Dance.all
    @categories = Category.all

    dances = @dances.map {|dance| [dance.id, dance]}.to_h
    @heat = Heat.group(:dance_id, :category).minimum(:number).
      group_by {|(dance_id, category), heat|
        category == 'Open' ? dances[dance_id].open_category : dances[dance_id].closed_category
      }.map {|category, heats| [category, heats.map(&:last).min]}.to_h  
  end

  def update
    @event = Event.last
    @event.update! params.require(:event).permit(:name, :location, :date, :heat_range_cat, :heat_range_level, :heat_range_age, :intermix)
    redirect_to  settings_event_index_path , notice: "Event was successfully updated."
  end
end
