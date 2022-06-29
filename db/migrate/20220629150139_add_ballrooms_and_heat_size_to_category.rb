class AddBallroomsAndHeatSizeToCategory < ActiveRecord::Migration[7.0]
  def change
    add_column :categories, :ballrooms, :integer
    add_column :categories, :max_heat_size, :integer
  end
end
