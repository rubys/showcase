class CreateEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :events do |t|
      t.string :name
      t.string :location
      t.string :date
      t.integer :heat_range_cat
      t.integer :heat_range_level
      t.integer :heat_range_age

      t.timestamps
    end
  end
end
