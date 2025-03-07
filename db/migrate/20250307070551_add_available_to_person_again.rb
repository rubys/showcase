class AddAvailableToPersonAgain < ActiveRecord::Migration[8.0]
  def change
    add_column :people, :available, :string, null: true
  end
end
