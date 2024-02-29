class AddHeatOrder < ActiveRecord::Migration[7.1]
  def change
    add_column :events, :heat_order, :string, default: 'L'
  end
end
