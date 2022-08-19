class AddStudentCostsToStudios < ActiveRecord::Migration[7.0]
  def change
    add_column :studios, :student_registration_cost, :decimal, precision: 7, scale: 2
    add_column :studios, :student_heat_cost, :decimal, precision: 7, scale: 2
    add_column :studios, :student_solo_cost, :decimal, precision: 7, scale: 2
    add_column :studios, :student_multi_cost, :decimal, precision: 7, scale: 2
  end
end
