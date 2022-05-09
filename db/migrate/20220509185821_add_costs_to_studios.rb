class AddCostsToStudios < ActiveRecord::Migration[7.0]
  def change
    add_column :studios, :heat_cost, :decimal, precision: 7, scale: 2
    add_column :studios, :solo_cost, :decimal, precision: 7, scale: 2
    add_column :studios, :multi_cost, :decimal, precision: 7, scale: 2
  end
end
