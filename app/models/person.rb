class Person < ApplicationRecord
  self.inheritance_column = nil

  normalizes :name, with: -> name do
    name.strip.gsub(/\s+/, ' ').gsub(/\s*,\s*/, ', ')
  end

  normalizes :available, with: -> { _1.presence }

  # Rails 8.0 compatible ordering scope
  scope :by_name, -> { order(arel_table[:name]) }

  validates :name, presence: true, uniqueness: { scope: :type }
  validates :back, allow_nil: true, uniqueness: true

  validates :name, format: { without: /&/, message: 'only one name per person' }
  validates :name, format: { without: / and /, message: 'only one name per person' }

  validates :level, presence: true, if: -> {type == 'Student'}
  
  before_save :cleanup_orphaned_options, if: :package_id_changed?

  belongs_to :studio, optional: false
  belongs_to :level, optional: true
  belongs_to :age, optional: true
  belongs_to :exclude, class_name: 'Person', optional: true
  has_many :excluded_by, class_name: 'Person', foreign_key: :exclude_id, dependent: :nullify
  belongs_to :package, class_name: 'Billable', optional: true
  belongs_to :table, optional: true

  belongs_to :invoice_to, class_name: 'Person', optional: true
  has_many :responsible_for, class_name: 'Person', foreign_key: :invoice_to_id, dependent: :nullify

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
  has_many :answers, dependent: :destroy

  accepts_nested_attributes_for :answers

  has_many :scores, dependent: :destroy, foreign_key: :judge_id
  has_many :payments, dependent: :destroy

  # Get people who have access to an option (either directly selected or through package includes)
  scope :with_option, ->(option_id) {
    left_joins(:options)
      .left_joins(package: { package_includes: :option })
      .where(
        "person_options.option_id = :option_id OR package_includes.option_id = :option_id",
        option_id: option_id
      )
      .distinct
  }

  # Get people who have access to an option but no table assignment for it
  scope :with_option_unassigned, ->(option_id) {
    # Use raw SQL to handle the complex join logic for finding people with the option
    # but without a table assignment
    joins(<<-SQL)
      LEFT JOIN person_options ON person_options.person_id = people.id 
        AND person_options.option_id = #{option_id.to_i}
      LEFT JOIN billables AS packages ON packages.id = people.package_id
      LEFT JOIN package_includes ON package_includes.package_id = packages.id
        AND package_includes.option_id = #{option_id.to_i}
    SQL
    .where(<<-SQL)
      (person_options.option_id = #{option_id.to_i} OR package_includes.option_id = #{option_id.to_i})
      AND (person_options.table_id IS NULL OR person_options.id IS NULL)
    SQL
    .distinct
  }

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
      Entry.distinct(:follow_id).pluck(:follow_id) +
      Formation.pluck(:person_id)).uniq
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
    # Franchisee and Studio Staff don't have studio defaults, fall through to type lookup

    self.package_id ||= Billable.where(type: type).ordered.pick(:id)
  end

  def default_package!
    default_package
    save! if changed?
  end

  def active?
    case type
    when 'Guest', 'Franchisee', 'Studio Staff'
      package_id != nil or not Billable.where(type: type).exists?
    when 'Student', 'Professional'
      return true if Formation.where(person_id: id).exists?
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

  # Get all questions for this person based on their package and selected options
  def applicable_questions
    # Return pre-calculated questions if available (used for dynamic updates)
    return @calculated_questions if defined?(@calculated_questions)

    question_ids = Set.new

    # Questions from package
    if package
      package.package_includes.each do |pi|
        question_ids.merge(pi.option.questions.pluck(:id))
      end
    end

    # Questions from directly selected options
    options.each do |person_option|
      question_ids.merge(person_option.option.questions.pluck(:id))
    end

    Question.where(id: question_ids.to_a).ordered
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

  # Compute version metadata for SPA staleness detection
  # Used by both version_check and heats_data endpoints to ensure consistency
  # Includes heats, this judge's updated_at, and event updated_at
  # @return [Hash] Version metadata with :max_updated_at and :heat_count
  def scoring_version_metadata
    event = Event.current
    heats_updated_at = Heat.where('number >= ?', 1).maximum(:updated_at)
    heat_count = Heat.where('number >= ?', 1).count

    # Include judge and event updated_at in the max calculation
    # This detects changes to judge preferences or event settings
    timestamps = [heats_updated_at, updated_at, event&.updated_at].compact
    max_updated_at = timestamps.max

    {
      max_updated_at: max_updated_at&.iso8601(3),
      heat_count: heat_count
    }
  end

  private

  def cleanup_orphaned_options
    return unless package_id_was.present? # Only if person had a package before

    old_package = Billable.find_by(id: package_id_was)
    return unless old_package

    # Get options that were included in the old package
    old_package_option_ids = old_package.package_includes.pluck(:option_id)

    # Get options that are included in the new package (if any)
    new_package_option_ids = package&.package_includes&.pluck(:option_id) || []

    # Options that were in old package but not in new package
    removed_option_ids = old_package_option_ids - new_package_option_ids

    # Clean up PersonOption records for removed options
    removed_option_ids.each do |option_id|
      person_option = options.find_by(option_id: option_id)
      if person_option && person_option.table_id.nil?
        # Only cleanup if not seated at a table (to avoid disrupting current seating)
        PersonOption.cleanup_if_only_from_package(person_option)
      end
      # If seated, we'll leave it for now but it will be cleaned up when unseated
    end
  end
end
