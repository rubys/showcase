class AddSemiFinalsToMultis < ActiveRecord::Migration[7.0]
  def change
    add_column :dances, :semi_finals, :boolean, default: false
  end
end
