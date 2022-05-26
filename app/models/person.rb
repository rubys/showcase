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

  def self.active
    (Entry.distinct(:lead_id).pluck(:lead_id) + 
      Entry.distinct(:follow_id).pluck(:follow_id) + 
      Entry.distinct(:follow_id).pluck(:follow_id)).uniq
  end

  def default_package
    self.package_id = nil unless package&.type == type

    if type == 'Student'
      self.package_id ||= studio&.default_student_package_id
    elsif type == 'Professional'
      self.package_id ||= studio&.default_professional_package_id
    elsif type == 'Guest'
      self.package_id ||= studio&.default_guest_package_id
    end

    self.package_id ||= Billable.where(type: type).order(:order).pluck(:id).first
  end

  def default_package!
    default_package
    save! if changed?
  end

  def active?
    case type
    when 'Judge', 'Emcee'
      true
    when 'Guest'
      package_id != nil or not Billable.where(type: 'Guest').exists?
    else
      if role == 'Leader'
        lead_entries.exists? or follow_entries.exists?
      else
        follow_entries.exists? or lead_entries.exists?
      end
    end
  end
end
