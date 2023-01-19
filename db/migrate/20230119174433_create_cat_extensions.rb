class CreateCatExtensions < ActiveRecord::Migration[7.0]
  def change
    create_table :cat_extensions do |t|
      t.references :category, null: false, foreign_key: true
      t.integer :start_heat
      t.integer :part
      t.integer :order
      t.string :day
      t.string :time

      t.timestamps
    end
  end
end
