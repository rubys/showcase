module Printable
  def heat_sheets
    @people ||= Person.where(type: ['Student', 'Professional']).order(:name)
    @heats = Heat.includes(:dance, entry: [:level, :age, :lead, :follow]).all.order(:number)
    @layout = 'mx-0'
    @nologo = true
  end

  def score_sheets
    @judges = Person.where(type: 'Judge').order(:name)
    @people ||= Person.joins(:studio).where(type: 'Student').order('studios.name, name')
    @heats = Heat.includes(:scores, :dance, entry: [:level, :age, :lead, :follow]).all.order(:number)
    @layout = 'mx-0'
    @nologo = true
  end
end