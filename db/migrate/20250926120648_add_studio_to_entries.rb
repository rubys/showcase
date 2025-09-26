class AddStudioToEntries < ActiveRecord::Migration[8.0]
  def change
    add_reference :entries, :studio, null: true, foreign_key: true
  end
end
