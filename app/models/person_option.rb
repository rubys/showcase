class PersonOption < ApplicationRecord
  belongs_to :person
  belongs_to :option, class_name: 'Billable'
  belongs_to :table, optional: true
  
  validate :table_belongs_to_same_option
  
  # Clean up PersonOption records that exist only because of package includes
  # Returns true if the record was destroyed, false if it was kept
  def self.cleanup_if_only_from_package(person_option)
    return false unless person_option
    
    person = person_option.person
    option_id = person_option.option_id
    
    # Check if person has this option through their package
    has_through_package = person.package&.package_includes&.exists?(option_id: option_id)
    
    if has_through_package
      # They have it through package - remove the record
      person_option.destroy!
      true
    else
      # They selected it directly - just clear the table if needed
      person_option.update!(table_id: nil) if person_option.table_id
      false
    end
  end
  
  # Find or create a PersonOption record for table assignment
  def self.find_or_create_for_table_assignment(person_id:, option_id:)
    find_or_create_by(person_id: person_id, option_id: option_id)
  end
  
  private
  
  def table_belongs_to_same_option
    if table.present? && table.option_id != option_id
      errors.add(:table, "must belong to the same option")
    end
  end
end
