class Person < ApplicationRecord
  self.inheritance_column = nil

  normalizes :name, with: -> name do
    name.strip.gsub(/\s+/, ' ').gsub(/\s*,\s*/, ', ')
  end

  normalizes :available, with: -> { _1.presence }

  validates :name, presence: true, uniqueness: { scope: :type }
  validates :back, allow_nil: true, uniqueness: true

  validates :name, format: { without: /&/, message: 'only one name per person' }
  validates :name, format: { without: / and /, message: 'only one name per person' }

  validates :level, presence: true, if: -> {type == 'Student'}

  belongs_to :studio, optional: false
  belongs_to :level, optional: true
  belongs_to :age, optional: true
  belongs_to :exclude, class_name: 'Person', optional: true
  belongs_to :package, class_name: 'Billable', optional: true

  belongs_to :invoice_to, class_name: 'Person', optional: true
  has_many :responsible_for, class_name: 'Person', foreign_key: :invoice_to_id

  has_one :judge, required: false, dependent: :destroy

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

  def self.display_name(name)
    name && name.split(/,\s*/).rotate.join(' ')
  end

  def display_name
    name && name.split(/,\s*/).rotate.join(' ')
  end

  def first_name
    name && name.split(/,\s*/).last
  end

  def last_name
    name && name.split(/,\s*/).first
  end

  def back_name
    names = name.split(/,\s*/)
    "#{names.last.gsub(' ', '')[0..5]}#{names.first[0]}"
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
    when 'Guest'
      package_id != nil or not Billable.where(type: 'Guest').exists?
    when 'Student', 'Professional'
      if role == 'Leader'
        not lead_entries.empty? or not follow_entries.empty?
      else
        not follow_entries.empty? or not lead_entries.empty?
      end
    else
      true
    end
  end

  def present?
    judge ? judge.present : true
  end

  def show_assignments
    judge ? judge.show_assignments : 'first'
  end

  def sort_order
    judge ? judge.sort : 'back'
  end

  # don't double bill a person for included options
  def selected_options
    options = self.options.map(&:option)
    included = self.package&.package_includes&.map(&:option)&.map(&:id) || []
    options.reject {|option| included.include? option.id}
  end

  def eligible_heats(start_times)
    return Set.new(start_times) unless available

    avail_time = Time.parse(available[1..])

    if available[0] == '<'
      Set.new(start_times.select {|number, time| time && time < avail_time}.map(&:first))
    else
      Set.new(start_times.select {|number, time| time && time > avail_time}.map(&:first))
    end
  end

  def self.nobody
    person = Person.find_or_create_by(id: 0)

    if not person.name
      person.name = 'Nobody'
      person.type = 'Placeholder'
      person.role = 'both'
      person.studio = Studio.find(0)
      person.save!
    end

    person
  end
end
