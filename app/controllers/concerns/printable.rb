module Printable
  def heat_sheets
    @people ||= Person.where(type: ['Student', 'Professional']).order(:name)
    @heats = Heat.includes(:dance, entry: [:level, :age, :lead, :follow]).all.order(:number)

    @heatlist = @people.map {|person| [person, []]}.to_h
    @heats.each do |heat|
      @heatlist[heat.lead] << heat.id rescue nil
      @heatlist[heat.follow] << heat.id rescue nil
    end

    Formation.includes(:person, solo: :heat).each do |formation|
      @heatlist[formation.person] << formation.solo.heat.id rescue nil
    end

    @layout = 'mx-0 px-5'
    @nologo = true
    @event = Event.last
  end

  def score_sheets
    @judges = Person.where(type: 'Judge').order(:name)
    @people ||= Person.joins(:studio).where(type: 'Student').order('studios.name, name')
    @heats = Heat.includes(:scores, :dance, entry: [:level, :age, :lead, :follow]).all.order(:number)
    @layout = 'mx-0 px-5'
    @nologo = true
    @event = Event.last
  end
end
