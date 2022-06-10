class AddBackNumbersToEvent < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :backnums, :boolean, default: true
  end
end
