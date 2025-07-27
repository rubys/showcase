class Table < ApplicationRecord
  belongs_to :option, class_name: 'Billable', optional: true
  has_many :people, dependent: :nullify
  has_many :person_options
  
  before_destroy :cleanup_person_options

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

  # Computed table size using priority: table.size > option.table_size > event.table_size > 10
  def computed_table_size
    return size if size && size > 0
    return option.computed_table_size if option_id && option&.computed_table_size
    Event.current&.table_size || 10
  end
  
  private
  
  def cleanup_person_options
    return unless option_id
    
    # Clean up PersonOption records for people who only have the option through their package
    person_options.includes(:person => {:package => :package_includes}).find_each do |person_option|
      PersonOption.cleanup_if_only_from_package(person_option)
    end
  end
end
