class AddOptionSupportToTables < ActiveRecord::Migration[8.0]
  def up
    # Add option_id to tables to associate tables with specific options (e.g., dinner tables)
    add_reference :tables, :option, foreign_key: { to_table: :billables }, null: true
    
    # Add table_id to person_options to assign people to specific tables at an option event
    add_reference :person_options, :table, foreign_key: true, null: true
    
    # Update the unique constraint to include option_id
    remove_index :tables, [:row, :col] if index_exists?(:tables, [:row, :col])
    add_index :tables, [:row, :col, :option_id], unique: true unless index_exists?(:tables, [:row, :col, :option_id])
  end
  
  def down
    # Remove the new index and restore the old one
    remove_index :tables, [:row, :col, :option_id] if index_exists?(:tables, [:row, :col, :option_id])
    add_index :tables, [:row, :col], unique: true unless index_exists?(:tables, [:row, :col])
    
    # Remove the references
    remove_reference :person_options, :table, foreign_key: true
    remove_reference :tables, :option, foreign_key: { to_table: :billables }
  end
end
