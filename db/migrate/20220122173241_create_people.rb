class CreatePeople < ActiveRecord::Migration[7.0]
  def change
    create_table :people do |t|
      t.string :name
      t.references :studio, null: false, foreign_key: true
      t.string :type
      t.integer :back
      t.string :level
      t.string :category
      t.string :role
      t.boolean :friday_dinner
      t.boolean :saturday_lunch
      t.boolean :saturday_dinner

      t.timestamps
    end
  end
end
