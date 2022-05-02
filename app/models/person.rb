class Person < ApplicationRecord
  self.inheritance_column = nil

  validates :name, presence: true, uniqueness: true
  validates :back, allow_nil: true, uniqueness: true
  
  belongs_to :studio, optional: true
  belongs_to :level, optional: true
  belongs_to :age, optional: true
  belongs_to :exclude, class_name: 'Person', optional: true
  belongs_to :package, class_name: 'Billable', optional: true

  has_many :lead_entries, class_name: 'Entry', foreign_key: :lead_id,
    dependent: :destroy
  has_many :follow_entries, class_name: 'Entry', foreign_key: :follow_id,
    dependent: :destroy
  has_many :instructor_entries, class_name: 'Entry', foreign_key: :instructor_id,
    dependent: :nullify
  has_many :formations, dependent: :destroy
  has_many :options, class_name: 'PersonOption', foreign_key: :person_id,
    dependent: :destroy

  has_many :scores, dependent: :destroy, foreign_key: :judge_id

  def display_name
    name.split(/,\s*/).rotate.join(' ')
  end

  def first_name
    name.split(/,\s*/).last
  end

  def join(person)
    if name.split(',').first == person.name.split(',').first
      "#{first_name} and #{person.display_name}"
    else
      "#{display_name} and #{person.display_name}"
    end
  end
end
