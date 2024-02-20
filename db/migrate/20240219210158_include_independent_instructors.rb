class IncludeIndependentInstructors < ActiveRecord::Migration[7.1]
  def change
    add_column :events, :independent_instructors, :boolean, default: false
    add_column :people, :independent, :boolean, default: false
  end
end
