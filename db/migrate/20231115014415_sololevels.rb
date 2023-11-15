class Sololevels < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :include_open, :boolean, default: true
    add_column :events, :include_closed, :boolean, default: true
    add_reference :events, :solo_level, null: true, foreign_key: {to_table: :levels}
  end
end
