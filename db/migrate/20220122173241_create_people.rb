class CreatePeople < ActiveRecord::Migration[7.0]
  def change
    create_table :people do |t|
      t.string :name
      t.references :studio, null: true, foreign_key: true
      t.string :type
      t.integer :back
      t.references :level, foreign_key: true
      t.references :age, foreign_key: true
      t.string :role

      t.timestamps
    end
  end
end
