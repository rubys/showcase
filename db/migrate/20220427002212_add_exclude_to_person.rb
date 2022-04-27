class AddExcludeToPerson < ActiveRecord::Migration[7.0]
  def change
    add_reference :people, :exclude, null: true, foreign_key: {to_table: :people}
  end
end
