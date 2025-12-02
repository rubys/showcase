class AddAgeCoupleColumnsToMultiLevels < ActiveRecord::Migration[8.1]
  def change
    add_column :multi_levels, :start_age, :integer
    add_column :multi_levels, :stop_age, :integer
    add_column :multi_levels, :couple_type, :string
  end
end
