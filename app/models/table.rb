class Table < ApplicationRecord
  belongs_to :option, class_name: 'Billable', optional: true
  has_many :people, dependent: :nullify
  has_many :person_options

  validates :number, presence: true, uniqueness: { scope: :option_id }
  validates :row, uniqueness: { scope: [:col, :option_id], message: "and column combination already taken" }, allow_nil: true

  def name
    return "Empty" if people.empty?
    
    people.joins(:studio).pluck('studios.name').uniq.sort.join(', ')
  end
end
