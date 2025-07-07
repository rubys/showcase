class PersonOption < ApplicationRecord
  belongs_to :person
  belongs_to :option, class_name: 'Billable'
  belongs_to :table, optional: true
  
  validate :table_belongs_to_same_option
  
  private
  
  def table_belongs_to_same_option
    if table.present? && table.option_id != option_id
      errors.add(:table, "must belong to the same option")
    end
  end
end
