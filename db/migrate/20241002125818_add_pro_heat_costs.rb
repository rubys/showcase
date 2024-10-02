class AddProHeatCosts < ActiveRecord::Migration[7.1]
  def change
    add_column :events, :pro_heat_cost, :decimal, precision: 7, scale: 2
    add_column :events, :pro_solo_cost, :decimal, precision: 7, scale: 2
    add_column :events, :pro_multi_cost, :decimal, precision: 7, scale: 2
  end
end
