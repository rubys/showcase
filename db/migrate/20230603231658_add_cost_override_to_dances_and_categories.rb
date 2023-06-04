class AddCostOverrideToDancesAndCategories < ActiveRecord::Migration[7.0]
  def change
    add_column :dances, :cost_override, :decimal, precision: 7, scale: 2
    add_column :categories, :cost_override, :decimal, precision: 7, scale: 2
  end
end
