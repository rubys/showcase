class AddHeatLengthToEvents < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :heat_length, :integer
  end
end
