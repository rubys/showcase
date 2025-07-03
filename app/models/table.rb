class Table < ApplicationRecord
  has_many :people, dependent: :nullify

  validates :number, presence: true, uniqueness: true
  validates :row, uniqueness: { scope: :col, message: "and column combination already taken" }, allow_nil: true

  def name
    return "Empty" if people.empty?
    
    people.joins(:studio).pluck('studios.name').uniq.sort.join(', ')
  end
end
