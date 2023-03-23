class RoutineCategories < ActiveRecord::Migration[7.0]
  def change
    add_column :categories, :routines, :boolean
    add_column :categories, :duration, :integer

    add_reference :solos, :category_override, foreign_key: {to_table: :categories}
  end
end
