class EventController < ApplicationController
  def root
    @judges = Person.where(type: 'Judge')
    @emcees = Person.where(type: 'Emcee')
  end
end
