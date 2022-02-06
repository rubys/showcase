class CreateEntries < ActiveRecord::Migration[7.0]
  def change
    create_table :entries do |t|
      t.integer :count
      t.string :category
      t.references :dance, null: false, foreign_key: true
      t.references :age, null: false, foreign_key: true
      t.references :level, null: false, foreign_key: true
      t.references :lead, null: false, foreign_key: {to_table: :people}
      t.references :follow, null: false, foreign_key: {to_table: :people}

      t.timestamps
    end
  end
end
