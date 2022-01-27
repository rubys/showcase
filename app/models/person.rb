class Person < ApplicationRecord
  self.inheritance_column = nil

  validates :name, presence: true, uniqueness: true
  validates :back, allow_nil: true, uniqueness: true
  
  belongs_to :studio, optional: true
  has_many :lead_entries, class_name: 'Entry', foreign_key: :lead_id
  has_many :follow_entries, class_name: 'Entry', foreign_key: :follow_id

  def display_name
    name.split(/,\s*/).rotate.join(' ')
  end
end
