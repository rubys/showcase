class Addtimesoption < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :include_times, :boolean, default: true
  end
end
