class CreateSolos < ActiveRecord::Migration[7.0]
  def change
    create_table :solos do |t|
      t.references :heat, null: false, foreign_key: true
      t.references :combo_dance, null: true, foreign_key: {to_table: :dances}
      t.integer :order

      t.timestamps
    end
  end
end
