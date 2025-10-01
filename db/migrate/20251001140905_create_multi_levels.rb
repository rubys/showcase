class CreateMultiLevels < ActiveRecord::Migration[8.0]
  def change
    create_table :multi_levels do |t|
      t.string :name
      t.references :dance, null: false, foreign_key: true
      t.integer :start_level
      t.integer :stop_level

      t.timestamps
    end
  end
end
