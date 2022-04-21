class CreateFormations < ActiveRecord::Migration[7.0]
  def change
    create_table :formations do |t|
      t.references :person, null: false, foreign_key: true
      t.references :solo, null: false, foreign_key: true

      t.timestamps
    end
  end
end
