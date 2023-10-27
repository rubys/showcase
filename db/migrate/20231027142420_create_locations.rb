class CreateLocations < ActiveRecord::Migration[7.0]
  def change
    create_table :locations do |t|
      t.string :key
      t.string :name
      t.string :logo
      t.float :latitude
      t.float :longitude
      t.references :user, null: true, foreign_key: true

      t.timestamps
    end
  end
end
