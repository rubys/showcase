class AddOnFloorToFormations < ActiveRecord::Migration[7.0]
  def change
    add_column :formations, :on_floor, :boolean, default: true
  end
end
