class AddMaxHeatSizeToEvent < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :max_heat_size, :integer
  end
end
