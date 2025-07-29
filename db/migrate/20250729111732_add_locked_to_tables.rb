class AddLockedToTables < ActiveRecord::Migration[8.0]
  def change
    add_column :tables, :locked, :boolean, default: false
  end
end
