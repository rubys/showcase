class CreateTables < ActiveRecord::Migration[8.0]
  def change
    create_table :tables do |t|
      t.integer :number
      t.integer :row
      t.integer :col
      t.integer :size

      t.timestamps
    end
    
    add_index :tables, [:row, :col], unique: true
    
    add_reference :people, :table, null: true, foreign_key: true
    
    add_column :events, :table_size, :integer
  end
end
