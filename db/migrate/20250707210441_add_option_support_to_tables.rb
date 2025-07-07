class AddOptionSupportToTables < ActiveRecord::Migration[8.0]
  def change
    # Add option_id to tables to associate tables with specific options (e.g., dinner tables)
    add_reference :tables, :option, foreign_key: { to_table: :billables }, null: true
    
    # Add table_id to person_options to assign people to specific tables at an option event
    add_reference :person_options, :table, foreign_key: true, null: true
  end
end
