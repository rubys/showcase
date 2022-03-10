class AddCurrentHeatToEvents < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :current_heat, :integer
  end
end
