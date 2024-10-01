class AddStudioCostToAgenda < ActiveRecord::Migration[7.1]
  def change
    add_column :categories, :studio_cost_override, :decimal, precision: 7, scale: 2
  end
end
