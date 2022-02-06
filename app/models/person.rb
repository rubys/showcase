class Person < ApplicationRecord
  self.inheritance_column = nil

  validates :name, presence: true, uniqueness: true
  validates :back, allow_nil: true, uniqueness: true
  
  belongs_to :studio, optional: true
  belongs_to :level, optional: true
  belongs_to :age, optional: true

  has_many :lead_entries, class_name: 'Entry', foreign_key: :lead_id,
    dependent: :destroy
  has_many :follow_entries, class_name: 'Entry', foreign_key: :follow_id,
    dependent: :destroy

  def display_name
    name.split(/,\s*/).rotate.join(' ')
  end
end
