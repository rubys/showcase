class AddAvailableToPerson < ActiveRecord::Migration[8.0]
  def change
    add_column :people, :available, :string, allow_nil: true
  end
end
