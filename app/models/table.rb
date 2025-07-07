class Table < ApplicationRecord
  belongs_to :option, class_name: 'Billable', optional: true
  has_many :people, dependent: :nullify
  has_many :person_options

  validates :number, presence: true, uniqueness: { scope: :option_id }
  validates :row, uniqueness: { scope: [:col, :option_id], message: "and column combination already taken" }, allow_nil: true

  def name
    if option_id
      # For option tables, get people through person_options
      person_options_at_table = person_options.includes(:person => :studio)
      return "Empty" if person_options_at_table.empty?
      
      studio_names = person_options_at_table.map { |po| po.person.studio.name }.uniq.sort
      studio_names.join(', ')
    else
      # For main event tables, use direct people association
      return "Empty" if people.empty?
      
      people.joins(:studio).pluck('studios.name').uniq.sort.join(', ')
    end
  end
end
