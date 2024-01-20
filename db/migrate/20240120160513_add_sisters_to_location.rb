class AddSistersToLocation < ActiveRecord::Migration[7.1]
  def change
    add_column :locations, :sisters, :string
  end
end
