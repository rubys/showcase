class CreateHeats < ActiveRecord::Migration[7.0]
  def change
    create_table :heats do |t|
      t.integer :number
      t.references :entry, null: false, foreign_key: true

      t.timestamps
    end
  end
end
