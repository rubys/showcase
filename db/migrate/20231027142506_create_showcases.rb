class CreateShowcases < ActiveRecord::Migration[7.0]
  def change
    create_table :showcases do |t|
      t.integer :year
      t.string :key
      t.string :name
      t.references :location, null: false, foreign_key: true

      t.timestamps
    end
  end
end
